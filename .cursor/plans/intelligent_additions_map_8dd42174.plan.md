---
name: Intelligent Additions Map
overview: Implement a map system that automatically detects new rental listing additions by comparing Rank 1 vs Rank 2 data in SQL, using a geocoding cache for performance, and displaying results with color-coded markers (green=addition, grey=existing).
todos:
  - id: update_geocoding_script
    content: "Update geocode_listings.py: Switch to SUPABASE_URI, add address_key normalization, filter to Rank 1 listings, improve error handling"
    status: completed
  - id: update_map_html
    content: "Update map.html: Consume feature column from view, enhance popup with unit/bed/bath/status, update legend and styling"
    status: completed
  - id: create_env_example
    content: Create .env.example with SUPABASE_URI and GMAPS_KEY
    status: completed
  - id: create_github_workflow
    content: Create .github/workflows/geocode-listings.yml for scheduled and manual execution
    status: completed
    dependencies:
      - update_geocoding_script
  - id: update_requirements
    content: Add python-dotenv to requirements.txt
    status: completed
  - id: update_readme
    content: Update README.md with new architecture, GitHub Actions setup, and configuration instructions
    status: completed
    dependencies:
      - update_geocoding_script
      - update_map_html
      - create_github_workflow
---

# Intelligent Additions Map Implementation

## Overview

This plan implements a three-tier architecture where SQL handles the business logic (Rank 1 vs Rank 2 comparison), Python manages geocoding efficiency, and the browser displays an interactive map. All "addition" detection happens in the database view, not in client code.

```mermaid
flowchart LR
    MakeScenario[Make.com Daily Upload] --> SupabaseDB[(Supabase DB)]
    SupabaseDB --> UnifiedView[unified_listings_vw]
    UnifiedView --> GeocodingScript[geocode_listings.py]
    GeocodingScript --> GoogleMaps[Google Maps API]
    GoogleMaps --> LocationsCache[(locations_cache)]
    UnifiedView --> MapView[map_listings_geojson VIEW]
    LocationsCache --> MapView
    MapView --> MapHTML[map.html Browser]
    MapHTML --> User[User sees Green=New, Grey=Existing]
    
    GithubActions[GitHub Actions Scheduler] -.->|triggers| GeocodingScript
```

## Key Changes from Existing Code

### Database Schema Updates (External - for reference only)

The Supabase view `marts.map_listings_geojson` will:

- Rank listings by `filename_date` per source (Rank 1 = latest, Rank 2 = previous)
- LEFT JOIN latest to previous to detect additions
- Join with `public.locations_cache` using **normalized address key** (`UPPER(TRIM(address))`)
- Output pre-formatted GeoJSON in a `feature` column

Cache table will use `address_key` as the primary key with UPPER/TRIM normalization.

---

## File Changes

### 1. Update [`geocode_listings.py`](geocode_listings.py)

**Changes:**

- Switch from separate connection params to single `SUPABASE_URI` env var
- Update query to use `address_key` = `UPPER(TRIM(address))` for normalization
- Filter to only geocode **Rank 1 (latest)** listings to avoid wasting API calls on old data
- Update cache insert to use `address_key` instead of `address`
- Rename `GOOGLE_MAPS_API_KEY` → `GMAPS_KEY` for consistency
- Add rate limiting (0.1s delay between requests)
- Improve error handling and progress reporting

**Query Logic:**

```sql
WITH ranked AS (
    SELECT address, 
           DENSE_RANK() OVER(PARTITION BY source_name ORDER BY filename_date DESC) as rnk
    FROM marts.unified_listings_vw
)
SELECT DISTINCT UPPER(TRIM(address)) as address_key
FROM ranked
WHERE rnk = 1
  AND UPPER(TRIM(address)) NOT IN (SELECT address_key FROM public.locations_cache)
LIMIT 50;
```

### 2. Update [`map.html`](map.html)

**Changes:**

- Update data fetching to use the `feature` column directly from `map_listings_geojson` view
- Remove manual GeoJSON construction (view provides it pre-formatted)
- Update configuration variables to use placeholders that match standard naming
- Enhance popup to show unit number, bed/bath, and status badge
- Improve circle styling with zoom-responsive sizing
- Update legend text from "Other" → "Existing Listing"

**Data Flow:**

```javascript
// OLD: Fetch flat columns, build GeoJSON in browser
const geojson = {
  features: data.map(listing => ({
    geometry: { coordinates: [listing.longitude, listing.latitude] },
    properties: { address: listing.address, ... }
  }))
};

// NEW: Fetch pre-built GeoJSON from 'feature' column
const geojson = {
  type: 'FeatureCollection',
  features: data.map(row => row.feature) // Already formatted!
};
```

### 3. Create `.env.example`

Document required environment variables for the geocoding script:

- `SUPABASE_URI` - PostgreSQL connection string
- `GMAPS_KEY` - Google Maps API key

### 4. Create `.github/workflows/geocode-listings.yml`

Set up GitHub Actions workflow to:

- Run on schedule (daily at 6:20 PM current NY Time, after Make.com uploads)
- Run on manual trigger (workflow_dispatch)
- Install Python dependencies
- Execute geocoding script with secrets from repository settings
- Report success/failure

**Workflow triggers:**

- Schedule: Daily at 6:20 PM current NY Time
- Manual: Via GitHub Actions UI
- Push to main (optional, for testing)

### 5. Update [`requirements.txt`](requirements.txt)

Add `python-dotenv` for local `.env` file support during development.

### 6. Update [`README.md`](README.md)

Update documentation to reflect:

- New architecture with rank-based addition detection
- Single `SUPABASE_URI` connection pattern
- GitHub Actions automation setup instructions
- Instructions for setting GitHub repository secrets
- Explanation of `address_key` normalization
- Map configuration with actual credential insertion points

---

## Environment Variables Setup

### Local Development (`.env` file)

```
SUPABASE_URI=postgresql://user:pass@host:5432/database
GMAPS_KEY=your_google_maps_api_key_here
```

### GitHub Actions (Repository Secrets)

Navigate to **Settings > Secrets and variables > Actions** and add:

- `SUPABASE_URI`
- `GMAPS_KEY`

### Map HTML (Direct editing)

Replace placeholders in `map.html`:

- `YOUR_MAPBOX_TOKEN`
- `YOUR_SUPABASE_URL`
- `YOUR_SUPABASE_ANON_KEY`

---

## Execution Flow

### Daily Automated Flow

1. **Morning**: Make.com uploads new CSV/PDF to Supabase
2. **6:20 PM current NY Time**: GitHub Actions triggers `geocode_listings.py`

   - Script identifies Rank 1 listings missing from cache
   - Geocodes them via Google Maps API
   - Inserts into `locations_cache` with normalized `address_key`

3. **User opens map**: 

   - `map.html` queries `marts.map_listings_geojson` view
   - View performs Rank 1 vs Rank 2 LEFT JOIN
   - Returns GeoJSON with `status: 'addition'` or `status: 'existing'`
   - Map renders green dots (additions) and grey dots (existing)

### Manual Execution

```bash
# Load environment variables
python geocode_listings.py
```

---

## Testing Strategy

1. **Geocoding Script**: Run locally with `.env` file, verify it connects and geocodes sample addresses
2. **GitHub Actions**: Manually trigger workflow via Actions tab, check logs
3. **Map Display**: Open `map.html` in browser, verify:

   - Points load correctly
   - Green = additions, Grey = existing
   - Popups show complete data (address, unit, rent, bed/bath, status)
   - Legend displays correctly

---

## Implementation Notes

- The **Supabase SQL is external** - this plan focuses only on the application layer files in this repo
- The view `marts.map_listings_geojson` must be created in Supabase before the map will work
- The cache table schema must use `address_key TEXT PRIMARY KEY` with UPPER/TRIM normalization
- GitHub Actions requires repository write access to run workflows
- Google Maps Geocoding API has usage limits - monitor via Google Cloud Console