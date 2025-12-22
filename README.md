# open-listings-map

An intelligent mapping tool that automatically detects and visualizes new rental listing additions by comparing the latest batch (Rank 1) against the previous batch (Rank 2) directly in SQL. The system geocodes addresses efficiently using a cache and displays results with color-coded markers.

## Architecture

```
Make.com → Supabase DB → Python Geocoder → Google Maps API
                ↓                               ↓
        unified_listings_vw              locations_cache
                ↓                               ↓
        map_listings_geojson VIEW (Rank 1 vs Rank 2 logic)
                ↓
        map.html (Green = Addition, Grey = Existing)
```

**Key Design Principle**: All "addition" detection logic lives in the SQL VIEW (`marts.map_listings_geojson`), not in application code. The map simply displays pre-computed results.

## Security & Authentication

This application uses **Supabase Authentication** with **Row Level Security (RLS)** to protect sensitive listing data. No separate backend server is required - all security is enforced at the database level.

### How It Works

1. **Database-Level Security**: Row Level Security (RLS) policies prevent unauthorized data access
   - Anonymous users receive 0 rows, even with the public API key
   - Only authenticated users with valid session tokens can read data
   - RLS policies are enforced server-side by Supabase

2. **Login Flow**:
   - Users visit `index.html` (login page)
   - Enter credentials created manually in Supabase Dashboard
   - Upon successful login, redirected to `map.html`
   - Session token automatically passed with all API requests

3. **Session Management**:
   - **Remember Me**: Unchecked = 1 hour session, Checked = 7 day session
   - **Auto-Logout**: Inactive sessions automatically logout after 30 minutes
   - **Timeout Warning**: Users receive a 2-minute warning before auto-logout
   - **Activity Tracking**: Mouse, keyboard, and scroll events reset the timeout

4. **Token Refresh**: Supabase automatically refreshes auth tokens to maintain active sessions

### Setup Instructions

**Prerequisites**: Complete these manual steps in your Supabase Dashboard before deploying:

1. **Enable Row Level Security**:
   - Run the SQL in [`sql/supabase_security_policies.sql`](sql/supabase_security_policies.sql) using the Supabase SQL Editor
   - This locks down `locations_cache` and `map_listings_geojson` to authenticated users only

2. **Create User Accounts**:
   - Navigate to Authentication > Users in Supabase Dashboard
   - Click "Add User" and manually create accounts for each team member
   - Share credentials securely (password manager, Signal, etc.)
   - **No public sign-up form** = no unauthorized access

See [`docs/SUPABASE_SETUP_GUIDE.md`](docs/SUPABASE_SETUP_GUIDE.md) for detailed step-by-step instructions.

### Security Benefits

- **No Exposed Backend**: Supabase handles all authentication server-side
- **Database-Level Protection**: RLS prevents data access even if someone bypasses the UI
- **Manual User Creation**: No public sign-up form to exploit
- **Session Expiration**: Auto-logout prevents abandoned sessions from remaining active
- **Token-Based Auth**: Tokens managed by Supabase, never exposed in client code
- **Safe Public Keys**: The Supabase Anon Key is safe to commit because RLS blocks data access

### Files Added for Security

- [`sql/supabase_security_policies.sql`](sql/supabase_security_policies.sql) - SQL script to enable RLS and create policies
- [`sql/user_visited_units.sql`](sql/user_visited_units.sql) - SQL script for visited units tracking table
- [`docs/SUPABASE_SETUP_GUIDE.md`](docs/SUPABASE_SETUP_GUIDE.md) - Step-by-step manual setup instructions
- `index.html` - Now serves as the login page with Supabase Auth integration
- `map.html` - Protected with auth guard, session timeout, logout button, and visited units tracking

## Features

- **Intelligent Addition Detection**: Automatically identifies new listings by comparing Rank 1 (latest) vs Rank 2 (previous) data per source
- **Efficient Geocoding**: Python script caches geocoded addresses with normalized keys to minimize Google Maps API costs
- **Automated Workflow**: GitHub Actions runs geocoding daily after Make.com uploads new data
- **Interactive Map**: Mapbox GL JS displays listings with:
  - 🟢 Green markers for new additions
  - ⚫ Dark grey markers for existing listings
  - Detailed popups with address, unit, rent, bed/bath, status, and source
- **Visited Units Tracking**: Per-user persistent checkboxes to track which units you've visited
  - Mark units as visited with a simple checkbox
  - State persists across sessions and devices indefinitely
  - Visited units are dimmed for easy visual identification
  - Secure per-user storage via Supabase with Row Level Security

## Prerequisites

- Python 3.11 or higher
- Google Maps API key ([Get one here](https://console.cloud.google.com/apis/credentials))
- Mapbox API token ([Get one here](https://account.mapbox.com/))
- Supabase project with the required database structure (see below)

### Required Supabase Database Structure

#### 1. Source View: `marts.unified_listings_vw`
Must include columns:
- `source_name` (TEXT)
- `address` (TEXT)
- `unit_number` (TEXT)
- `rent_price` (TEXT/NUMERIC) - The rent amount
- `bedrooms` (TEXT/NUMERIC) - Number of bedrooms
- `bathrooms` (TEXT/NUMERIC) - Number of bathrooms
- `filename_date` (DATE) - Used for ranking (CRITICAL for Rank 1 vs Rank 2 logic)

#### 2. Cache Table: `public.locations_cache`
```sql
CREATE TABLE public.locations_cache (
    address_key TEXT PRIMARY KEY,  -- Normalized: UPPER(TRIM(address))
    latitude FLOAT,
    longitude FLOAT,
    updated_at TIMESTAMP DEFAULT now()
);
```

#### 3. Smart View: `public.map_listings_geojson`
**IMPORTANT**: This view MUST be created in the `public` schema (not `marts`) for the Supabase REST API to expose it.

This view performs the Rank 1 vs Rank 2 comparison and outputs GeoJSON. The view must return a `feature` column containing pre-formatted GeoJSON Feature objects.

**Create with this SQL:**
```sql
CREATE OR REPLACE VIEW public.map_listings_geojson AS
WITH ranked_listings AS (
    SELECT
        v.source_name,
        v.address,
        v.unit_number,
        v.rent_price,
        v.bedrooms,
        v.bathrooms,
        DENSE_RANK() OVER(PARTITION BY v.source_name ORDER BY v.filename_date DESC) as date_rank
    FROM marts.unified_listings_vw v
),
latest_records AS (
    SELECT * FROM ranked_listings WHERE date_rank = 1
),
previous_records AS (
    SELECT * FROM ranked_listings WHERE date_rank = 2
)
SELECT
    l.source_name,
    l.address,
    l.unit_number,
    CASE 
        WHEN p.address IS NULL THEN 'addition'
        ELSE 'existing'
    END as status,
    jsonb_build_object(
        'type', 'Feature',
        'geometry', jsonb_build_object(
            'type', 'Point',
            'coordinates', jsonb_build_array(loc.longitude, loc.latitude)
        ),
        'properties', jsonb_build_object(
            'address', l.address,
            'unit', l.unit_number,
            'rent', l.rent_price,
            'bed', l.bedrooms,
            'bath', l.bathrooms,
            'source', l.source_name,
            'status', CASE WHEN p.address IS NULL THEN 'addition' ELSE 'existing' END
        )
    ) as feature
FROM latest_records l
LEFT JOIN previous_records p 
    ON l.source_name = p.source_name 
    AND l.address = p.address 
    AND l.unit_number = p.unit_number
INNER JOIN public.locations_cache loc 
    ON UPPER(TRIM(l.address)) = loc.address_key;

-- Grant access for public viewing
GRANT SELECT ON public.map_listings_geojson TO anon;
GRANT SELECT ON public.map_listings_geojson TO authenticated;
```

## Setup

### 1. Clone Repository

```bash
git clone <your-repo-url>
cd open-listings-map
```

### 2. Install Python Dependencies

```bash
pip install -r requirements.txt
```

### 3. Configure Environment Variables

#### For Local Development

Create a `.env` file in the project root:

```bash
# Supabase Database Connection
SUPABASE_URI=postgresql://postgres.your-project-ref:your-password@aws-0-us-east-1.pooler.supabase.com:5432/postgres

# Google Maps API Key
GMAPS_KEY=your_google_maps_api_key_here
```

**Note**: The `.env` file is gitignored and will not be committed.

#### For GitHub Actions

1. Go to your repository on GitHub
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Add the following repository secrets:
   - `SUPABASE_URI` - Your PostgreSQL connection string
   - `GMAPS_KEY` - Your Google Maps API key

### 4. Configure HTML Files

Both `index.html` and `map.html` need Supabase configuration:

**Edit `index.html` (lines ~180-182):**

```javascript
const SUPABASE_URL = 'https://your-project.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGc...'; // Your Supabase anonymous key
```

**Edit `map.html` (lines ~146-148):**

```javascript
const MAPBOX_TOKEN = 'pk.eyJ1Ijoi...'; // Your Mapbox public token
const SUPABASE_URL = 'https://your-project.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGc...'; // Your Supabase anonymous key
```

**Note**: The Supabase Anon Key is safe to commit to version control because Row Level Security (RLS) prevents unauthorized data access at the database level.

### 5. Set Up Supabase Security & Database

**IMPORTANT**: Complete security setup before proceeding. See [`docs/SUPABASE_SETUP_GUIDE.md`](docs/SUPABASE_SETUP_GUIDE.md) for detailed instructions.

#### Enable Authentication & Row Level Security

Run the SQL in [`sql/supabase_security_policies.sql`](sql/supabase_security_policies.sql) via Supabase SQL Editor to:
- Enable RLS on `locations_cache` table
- Create authentication policies
- Revoke anonymous access
- Grant access to authenticated users only

#### Set Up Visited Units Tracking (Optional)

Run the SQL in [`sql/user_visited_units.sql`](sql/user_visited_units.sql) via Supabase SQL Editor to:
- Create `user_visited_units` table to track which units each user has visited
- Enable Row Level Security so users only see their own visits
- Create indexes for fast queries
- Visited status persists indefinitely until manually unmarked

**This enables the checkbox feature** in unit popups to mark units as visited.

#### Create User Accounts

Navigate to Authentication > Users in Supabase Dashboard and manually create accounts for your team.

#### Create the Cache Table (if not already exists)

Run this in Supabase SQL Editor:

```sql
CREATE TABLE IF NOT EXISTS public.locations_cache (
    address_key TEXT PRIMARY KEY,
    latitude FLOAT,
    longitude FLOAT,
    updated_at TIMESTAMP DEFAULT now()
);

-- Disable RLS or create a read policy
ALTER TABLE public.locations_cache DISABLE ROW LEVEL SECURITY;
```

#### Create the Smart View

See the SQL in the "Required Supabase Database Structure" section above. Make sure to:
1. Create it in the `public` schema (not `marts`)
2. Match the column names from your `marts.unified_listings_vw`
3. Grant SELECT access to `anon` and `authenticated` roles

## Usage

### Automated Daily Workflow (Recommended)

The system runs automatically via GitHub Actions:

1. **Morning**: Make.com scenario uploads new CSV/PDFs to Supabase
2. **6:20 PM NY Time**: GitHub Actions triggers `geocode_listings.py`
   - Identifies Rank 1 (latest) listings missing from cache
   - Geocodes them via Google Maps API
   - Inserts into `locations_cache` with normalized `address_key`
3. **Anytime**: Open `map.html` to view the latest data

**Manual Trigger**: You can also trigger the workflow manually from the GitHub Actions tab.

### Manual Geocoding (Local)

Run the geocoding script locally:

```bash
python geocode_listings.py
```

The script will:
1. Connect to Supabase using `SUPABASE_URI`
2. Query for Rank 1 listings with missing geocodes (max 50 per run)
3. Geocode each address using Google Maps API (appends "New York, NY" for accuracy)
4. Store results in `public.locations_cache` with normalized `address_key` (UPPER/TRIM)
5. Print progress and summary statistics

**Rate Limiting**: The script includes a 0.1 second delay between API calls to be respectful to Google's servers.

### Viewing the Map

Open `map.html` in any web browser. The map will:

- Fetch pre-computed data from `marts.map_listings_geojson` view
- Display interactive points:
  - 🟢 **Green (#00E676)**: New additions (in Rank 1 but not in Rank 2)
  - ⚫ **Dark Grey (#37474F)**: Existing listings (in both Rank 1 and Rank 2)
- Show detailed popups on click with:
  - Address and unit number
  - Status badge (NEW ADDITION or EXISTING)
  - Rent amount
  - Bed/bath counts
  - Data source
- Zoom-responsive marker sizing (larger at higher zoom levels)

## How the Addition Detection Works

The "intelligence" of this system comes from SQL, not code:

1. **Ranking**: The view `public.map_listings_geojson` uses `DENSE_RANK()` to partition listings by `source_name` and order by `filename_date DESC`
   - Rank 1 = Latest batch (most recent filename_date per source)
   - Rank 2 = Previous batch (second most recent filename_date per source)
   
2. **Comparison**: A `LEFT JOIN` from Rank 1 to Rank 2 on `(source_name, address, unit_number)` reveals:
   - If the join finds a match → `status = 'existing'` (listing appears in both batches)
   - If the join returns NULL → `status = 'addition'` (new listing in latest batch only)

3. **Geocoding**: Only listings with cached coordinates are included via `INNER JOIN` with `public.locations_cache`
   - Run the Python geocoding script first to populate the cache
   - The script automatically geocodes Rank 1 listings missing from cache

4. **Output**: The view produces GeoJSON features with:
   - Coordinates from the cache
   - Status computed from the comparison
   - All listing details in the properties object

5. **Display**: The map simply reads `status` and applies colors:
   - `addition` → Green (#00E676)
   - `existing` → Dark Grey (#37474F)

## Address Normalization

To ensure consistent matching between the geocoding cache and the database view, all addresses are normalized using:

```sql
UPPER(TRIM(address))
```

This prevents duplicates caused by:
- Leading/trailing whitespace
- Case differences ("Main St" vs "MAIN ST")

The `locations_cache` table uses `address_key` as the primary key, storing the normalized version.

## Troubleshooting

### Authentication Issues

**"Cannot log in with valid credentials"**
- Verify the user account exists in Supabase Dashboard (Authentication > Users)
- Check email is confirmed (click three dots > Confirm email)
- Ensure RLS policies are created correctly (run `supabase_security_policies.sql`)
- Check browser console (F12) for detailed error messages

**"Map redirects to login immediately after successful login"**
- Session may not be persisting - check browser's localStorage is enabled
- Try checking "Remember me" for longer session duration
- Verify Supabase URL and Anon Key are correct in both `index.html` and `map.html`

**"Map shows no data after logging in"**
- RLS policies might be blocking authenticated users (run [`sql/supabase_security_policies.sql`](sql/supabase_security_policies.sql))
- Run in Supabase SQL Editor: `SELECT COUNT(*) FROM public.locations_cache;`
- Verify the policy grants SELECT to `authenticated` role
- Check the policy was created: `SELECT * FROM pg_policies WHERE tablename = 'locations_cache';`

**"Session expires too quickly"**
- Use the "Remember me" checkbox for 7-day sessions (default is 1 hour)
- Session timeout is set to 30 minutes of inactivity
- Activity is tracked: moving mouse, keyboard input, scrolling resets the timer

**"Auto-logout happens while actively using the map"**
- Check browser console for auth state change events
- Token refresh may be failing - verify internet connection
- Try logging out and back in to establish a fresh session

### Geocoding Script Issues

**"Error: SUPABASE_URI environment variable not set"**
- Ensure your `.env` file exists and contains `SUPABASE_URI`
- For GitHub Actions, verify the secret is added in repository settings

**"Error: GMAPS_KEY environment variable not set"**
- Add your Google Maps API key to `.env` or GitHub secrets
- Verify the key has Geocoding API enabled in Google Cloud Console

**"No addresses to geocode"**
- All active listings are already cached
- Or check if `marts.unified_listings_vw` has data with `filename_date` populated

### Map Display Issues

**"No listings found"**
- Verify `marts.map_listings_geojson` view exists and returns data
- Check browser console for Supabase connection errors
- Ensure Row Level Security (RLS) policies allow anonymous reads

**Points not displaying**
- Verify the `feature` column in the view contains valid GeoJSON
- Check that `locations_cache` has coordinates for the addresses
- Open browser DevTools → Network tab to inspect the Supabase query response

**Wrong colors showing**
- The view must compute `status` correctly in the GeoJSON properties
- Verify the Rank 1 vs Rank 2 LEFT JOIN logic in the SQL view

**"Failed to load resource: net::ERR_NAME_NOT_RESOLVED"**
- Double-check your Supabase URL in map.html is correct
- The URL should match your project URL exactly from the Supabase dashboard

**View not accessible via REST API**
- The view MUST be in the `public` schema, not `marts` or any other schema
- Supabase REST API only exposes tables/views in the `public` schema by default
- Recreate the view in public: `CREATE OR REPLACE VIEW public.map_listings_geojson AS ...`

**Column does not exist errors when creating view**
- Check your actual column names: `SELECT column_name FROM information_schema.columns WHERE table_name = 'unified_listings_vw'`
- Common differences: `rent_price` vs `ask_rent`, `bedrooms` vs `bed`, `bathrooms` vs `bath`
- Update the view SQL to match your exact column names

**Map hangs on "Loading listings..."**
- Check browser console (F12) for JavaScript errors
- Verify the view returns data: `SELECT COUNT(*) FROM public.map_listings_geojson;`
- If count is 0, check that addresses in cache match addresses in listings (case-sensitive, whitespace matters)
- Use address normalization: `UPPER(TRIM(address))`

## GitHub Actions Monitoring

View workflow runs:
1. Go to your repository on GitHub
2. Click **Actions** tab
3. Select **Geocode Listings** workflow
4. View run history, logs, and manually trigger runs

## File Structure

```
open-listings-map/
├── .github/
│   └── workflows/
│       └── geocode-listings.yml       # Automated daily geocoding
├── docs/                              # Documentation
│   ├── IMPLEMENTATION_SUMMARY.md      # Quick reference guide
│   ├── SUPABASE_SETUP_GUIDE.md        # Manual setup instructions
│   └── TESTING_GUIDE.md               # Testing procedures
├── sql/                               # Database scripts
│   ├── supabase_security_policies.sql # RLS policies for database security
│   └── user_visited_units.sql         # Visited units tracking table & policies
├── geocode_listings.py                # Python geocoding script
├── index.html                         # Login page with Supabase Auth
├── map.html                           # Protected interactive Mapbox map
├── requirements.txt                   # Python dependencies
└── README.md                          # This file
```

## Testing Your Setup

### 0. Test Authentication (Do This First!)

Before testing the map functionality, verify authentication is working:

```bash
# 1. Open index.html in a browser
# 2. You should see a login form (not a redirect)
# 3. Try logging in with invalid credentials - should show error
# 4. Log in with valid credentials (user created in Supabase)
# 5. Should redirect to map.html and load data
# 6. Click "Logout" button in bottom-right legend
# 7. Should return to login page
# 8. Try accessing map.html directly without logging in
# 9. Should automatically redirect to index.html
```

**Expected Behavior:**
- ✅ Login page shows modern form with email/password fields
- ✅ Invalid credentials show error message
- ✅ Valid credentials redirect to map
- ✅ Map loads and displays points
- ✅ Logout button returns to login page
- ✅ Direct access to map.html redirects to login if not authenticated
- ✅ Session persists across page refreshes (when "Remember me" checked)

**Test RLS in Supabase SQL Editor:**

```sql
-- This should show your policy
SELECT * FROM pg_policies WHERE tablename = 'locations_cache';

-- This returns data (you're authenticated in dashboard)
SELECT COUNT(*) FROM public.locations_cache;

-- But the JavaScript API with anon key (not logged in) gets 0 rows
```

### 1. Test Geocoding Script

```bash
python geocode_listings.py
```

Should output:
- Number of addresses found to geocode
- Progress for each address
- Success/failure summary

### 2. Verify Data in Supabase

```sql
-- Check cache has data
SELECT COUNT(*) FROM public.locations_cache;

-- Check view returns data
SELECT COUNT(*) FROM public.map_listings_geojson;

-- Sample the view output
SELECT 
    address, 
    status, 
    feature->>'type' as feature_type 
FROM public.map_listings_geojson 
LIMIT 5;
```

### 3. Test the Map

1. Open `map.html` in browser
2. Open DevTools (F12) → Console tab
3. Should see:
   - "Starting to fetch listings..."
   - "Found X listings"
   - "Successfully loaded X listings on map"
4. Map should display dots in Manhattan/NYC area
5. Click dots to see popups with listing details

## Common Setup Issues

**Column name mismatches**: Your `unified_listings_vw` might have different column names. Always check with:
```sql
SELECT column_name FROM information_schema.columns 
WHERE table_schema = 'marts' AND table_name = 'unified_listings_vw';
```

**Schema issues**: The REST API view must be in `public` schema. Views in other schemas won't be accessible.

**Address matching**: Geocoded addresses must match exactly (after normalization). Both the Python script and SQL view use `UPPER(TRIM(address))`.

**RLS policies**: If the view returns empty data via API but has data in SQL Editor, check Row Level Security policies on `locations_cache` and the view itself.

## Contributing

When making changes:
1. Test geocoding locally with `.env` file
2. Commit changes to a feature branch
3. Push to remote and create a pull request
4. Do NOT push directly to main branch

## License

MIT