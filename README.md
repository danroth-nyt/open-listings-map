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

## Features

- **Intelligent Addition Detection**: Automatically identifies new listings by comparing Rank 1 (latest) vs Rank 2 (previous) data per source
- **Efficient Geocoding**: Python script caches geocoded addresses with normalized keys to minimize Google Maps API costs
- **Automated Workflow**: GitHub Actions runs geocoding daily after Make.com uploads new data
- **Interactive Map**: Mapbox GL JS displays listings with:
  - 🟢 Green markers for new additions
  - ⚫ Dark grey markers for existing listings
  - Detailed popups with address, unit, rent, bed/bath, status, and source

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
- `ask_rent` (NUMERIC)
- `bed` (TEXT/NUMERIC)
- `bath` (TEXT/NUMERIC)
- `filename_date` (DATE) - Used for ranking

#### 2. Cache Table: `public.locations_cache`
```sql
CREATE TABLE public.locations_cache (
    address_key TEXT PRIMARY KEY,  -- Normalized: UPPER(TRIM(address))
    latitude FLOAT,
    longitude FLOAT,
    updated_at TIMESTAMP DEFAULT now()
);
```

#### 3. Smart View: `marts.map_listings_geojson`
This view performs the Rank 1 vs Rank 2 comparison and outputs GeoJSON. See the plan documentation or Supabase SQL editor for the full SQL definition. The view must return a `feature` column containing pre-formatted GeoJSON Feature objects.

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

### 4. Configure Map HTML

Edit `map.html` (lines 117-119) and replace the placeholders:

```javascript
const MAPBOX_TOKEN = 'pk.eyJ1Ijoi...'; // Your Mapbox public token
const SUPABASE_URL = 'https://your-project.supabase.co'; // Your Supabase URL
const SUPABASE_ANON_KEY = 'eyJhbGc...'; // Your Supabase anonymous key
```

### 5. Set Up Supabase Database

Execute the SQL to create the required cache table and smart view in your Supabase SQL Editor. The view must implement the Rank 1 vs Rank 2 logic as described in the architecture section.

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

1. **Ranking**: The view `marts.map_listings_geojson` uses `DENSE_RANK()` to partition listings by `source_name` and order by `filename_date DESC`
   - Rank 1 = Latest batch
   - Rank 2 = Previous batch
   
2. **Comparison**: A `LEFT JOIN` from Rank 1 to Rank 2 on `(source_name, address, unit_number)` reveals:
   - If the join finds a match → `status = 'existing'`
   - If the join returns NULL → `status = 'addition'` (new!)

3. **Output**: The view produces GeoJSON features with the `status` property already computed

4. **Display**: The map simply reads `status` and applies colors:
   - `addition` → Green
   - `existing` → Grey

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
│       └── geocode-listings.yml  # Automated daily geocoding
├── geocode_listings.py           # Python geocoding script
├── map.html                      # Interactive Mapbox map
├── requirements.txt              # Python dependencies
└── README.md                     # This file
```

## Contributing

When making changes:
1. Test geocoding locally with `.env` file
2. Commit changes to a feature branch
3. Push to remote and create a pull request
4. Do NOT push directly to main branch

## License

MIT