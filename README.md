# open-listings-map

A tool for geocoding and visualizing open listings data from Supabase.

## Features

- **Geocoding Script**: Python script that fetches addresses from Supabase, geocodes them using Google Maps API, and caches the results
- **Interactive Map**: HTML page with Mapbox GL JS that displays listings with color-coded status markers and detailed popups

## Prerequisites

- Python 3.7 or higher
- Google Maps API key
- Mapbox API token
- Supabase project with the following database structure:
  - `marts.unified_listings_vw` view with an `address` column
  - `public.locations_cache` table for storing geocoded locations
  - `map_listings_geojson` view/table with listing data including longitude, latitude, address, rent, source, and status

## Setup

### 1. Install Python Dependencies

```bash
pip install -r requirements.txt
```

### 2. Configure Environment Variables

Copy the example environment file and fill in your credentials:

```bash
cp .env.example .env
```

Edit `.env` and add your:
- Supabase connection details
- Google Maps API key

### 3. Configure Map HTML

Edit `map.html` and replace the placeholders:
- `YOUR_MAPBOX_TOKEN` - Your Mapbox access token
- `YOUR_SUPABASE_URL` - Your Supabase project URL
- `YOUR_SUPABASE_ANON_KEY` - Your Supabase anonymous key

## Usage

### Geocoding Listings

Run the geocoding script to fetch addresses and geocode them:

```bash
python geocode_listings.py
```

The script will:
1. Connect to your Supabase database
2. Fetch unique addresses from `marts.unified_listings_vw` that aren't in `public.locations_cache`
3. Geocode each address using Google Maps API (appending "New York, NY")
4. Insert the latitude and longitude into `public.locations_cache`

### Viewing the Map

Open `map.html` in a web browser. The map will:
- Fetch listings from `map_listings_geojson`
- Display points on the map:
  - **Green (#00E676)**: Listings with status 'addition'
  - **Dark Gray (#37474F)**: All other listings
- Show popups on click with address, rent, and source information

## Database Schema Requirements

### public.locations_cache

```sql
CREATE TABLE public.locations_cache (
    address TEXT PRIMARY KEY,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    geocoded_at TIMESTAMP
);
```

### marts.unified_listings_vw

Should be a view that includes at minimum:
- `address` (TEXT)

### map_listings_geojson

Should be a view or table that includes:
- `longitude` (DOUBLE PRECISION)
- `latitude` (DOUBLE PRECISION)
- `address` (TEXT)
- `rent` (NUMERIC or TEXT)
- `source` (TEXT)
- `status` (TEXT)

## License

MIT