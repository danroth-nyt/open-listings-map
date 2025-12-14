#!/usr/bin/env python3
"""
Geocode listings from Supabase using Google Maps API.

This script fetches unique addresses from marts.unified_listings_vw that are
missing from public.locations_cache, geocodes them using Google Maps API
(appending "New York, NY"), and inserts the latitude/longitude into the cache.
"""

import os
import sys
import psycopg2
import googlemaps
from datetime import datetime


def get_db_connection():
    """Create and return a database connection to Supabase."""
    try:
        conn = psycopg2.connect(
            host=os.environ.get('SUPABASE_HOST'),
            port=os.environ.get('SUPABASE_PORT', '5432'),
            database=os.environ.get('SUPABASE_DB'),
            user=os.environ.get('SUPABASE_USER'),
            password=os.environ.get('SUPABASE_PASSWORD')
        )
        return conn
    except Exception as e:
        print(f"Error connecting to database: {e}")
        sys.exit(1)


def get_gmaps_client():
    """Create and return a Google Maps client."""
    api_key = os.environ.get('GOOGLE_MAPS_API_KEY')
    if not api_key:
        print("Error: GOOGLE_MAPS_API_KEY environment variable not set")
        sys.exit(1)
    return googlemaps.Client(key=api_key)


def fetch_missing_addresses(conn):
    """
    Fetch unique addresses from marts.unified_listings_vw that are missing
    from public.locations_cache.
    
    Returns a list of unique addresses.
    """
    query = """
        SELECT DISTINCT ul.address
        FROM marts.unified_listings_vw ul
        LEFT JOIN public.locations_cache lc ON ul.address = lc.address
        WHERE lc.address IS NULL
        AND ul.address IS NOT NULL
        AND ul.address != ''
        ORDER BY ul.address
    """
    
    try:
        with conn.cursor() as cur:
            cur.execute(query)
            addresses = [row[0] for row in cur.fetchall()]
            return addresses
    except Exception as e:
        print(f"Error fetching addresses: {e}")
        return []


def geocode_address(gmaps_client, address):
    """
    Geocode an address using Google Maps API.
    Appends "New York, NY" to the address before geocoding.
    
    Returns a tuple of (latitude, longitude) or (None, None) if geocoding fails.
    """
    full_address = f"{address}, New York, NY"
    
    try:
        result = gmaps_client.geocode(full_address)
        if result and len(result) > 0:
            location = result[0]['geometry']['location']
            return location['lat'], location['lng']
        else:
            print(f"No results found for: {full_address}")
            return None, None
    except Exception as e:
        print(f"Error geocoding {full_address}: {e}")
        return None, None


def insert_location(conn, address, latitude, longitude):
    """
    Insert geocoded location into public.locations_cache.
    
    Returns True if successful, False otherwise.
    """
    query = """
        INSERT INTO public.locations_cache (address, latitude, longitude, geocoded_at)
        VALUES (%s, %s, %s, %s)
        ON CONFLICT (address) DO UPDATE
        SET latitude = EXCLUDED.latitude,
            longitude = EXCLUDED.longitude,
            geocoded_at = EXCLUDED.geocoded_at
    """
    
    try:
        with conn.cursor() as cur:
            cur.execute(query, (address, latitude, longitude, datetime.now()))
        conn.commit()
        return True
    except Exception as e:
        print(f"Error inserting location for {address}: {e}")
        conn.rollback()
        return False


def main():
    """Main execution function."""
    print("Starting geocoding process...")
    
    # Initialize connections
    conn = get_db_connection()
    gmaps_client = get_gmaps_client()
    
    # Fetch addresses needing geocoding
    print("Fetching addresses missing from cache...")
    addresses = fetch_missing_addresses(conn)
    
    if not addresses:
        print("No addresses to geocode. Exiting.")
        conn.close()
        return
    
    print(f"Found {len(addresses)} addresses to geocode.")
    
    # Geocode and insert each address
    success_count = 0
    fail_count = 0
    
    for i, address in enumerate(addresses, 1):
        print(f"Processing {i}/{len(addresses)}: {address}")
        
        lat, lng = geocode_address(gmaps_client, address)
        
        if lat is not None and lng is not None:
            if insert_location(conn, address, lat, lng):
                success_count += 1
                print(f"  ✓ Geocoded and cached: {lat}, {lng}")
            else:
                fail_count += 1
                print(f"  ✗ Failed to cache")
        else:
            fail_count += 1
            print(f"  ✗ Failed to geocode")
    
    # Summary
    print("\n" + "="*50)
    print(f"Geocoding complete!")
    print(f"Successfully geocoded and cached: {success_count}")
    print(f"Failed: {fail_count}")
    print("="*50)
    
    conn.close()


if __name__ == "__main__":
    main()
