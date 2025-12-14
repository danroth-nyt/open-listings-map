#!/usr/bin/env python3
"""
Geocode listings from Supabase using Google Maps API.

This script fetches unique addresses from Rank 1 (latest) listings in
marts.unified_listings_vw that are missing from public.locations_cache,
geocodes them using Google Maps API (appending "New York, NY"), and
inserts the normalized address_key with latitude/longitude into the cache.
"""

import os
import sys
import time
import psycopg2
import googlemaps
from datetime import datetime

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass  # dotenv not required in production


def get_db_connection():
    """Create and return a database connection to Supabase."""
    db_uri = os.environ.get('SUPABASE_URI')
    if not db_uri:
        print("Error: SUPABASE_URI environment variable not set")
        print("Expected format: postgresql://user:password@host:port/database")
        sys.exit(1)
    
    try:
        conn = psycopg2.connect(db_uri)
        return conn
    except Exception as e:
        print(f"Error connecting to database: {e}")
        sys.exit(1)


def get_gmaps_client():
    """Create and return a Google Maps client."""
    api_key = os.environ.get('GMAPS_KEY')
    if not api_key:
        print("Error: GMAPS_KEY environment variable not set")
        sys.exit(1)
    return googlemaps.Client(key=api_key)


def fetch_missing_addresses(conn):
    """
    Fetch unique addresses from Rank 1 (latest) listings in marts.unified_listings_vw
    that are missing from public.locations_cache.
    
    Returns a list of unique normalized address keys.
    """
    query = """
        WITH ranked AS (
            SELECT 
                address,
                DENSE_RANK() OVER(PARTITION BY source_name ORDER BY filename_date DESC) as rnk
            FROM marts.unified_listings_vw
            WHERE address IS NOT NULL
            AND TRIM(address) != ''
        )
        SELECT DISTINCT UPPER(TRIM(address)) as address_key
        FROM ranked
        WHERE rnk = 1
        AND UPPER(TRIM(address)) NOT IN (
            SELECT address_key FROM public.locations_cache
        )
        ORDER BY address_key
        LIMIT 50
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


def insert_location(conn, address_key, latitude, longitude):
    """
    Insert geocoded location into public.locations_cache using normalized address_key.
    
    Returns True if successful, False otherwise.
    """
    query = """
        INSERT INTO public.locations_cache (address_key, latitude, longitude, updated_at)
        VALUES (%s, %s, %s, %s)
        ON CONFLICT (address_key) DO UPDATE
        SET latitude = EXCLUDED.latitude,
            longitude = EXCLUDED.longitude,
            updated_at = EXCLUDED.updated_at
    """
    
    try:
        with conn.cursor() as cur:
            cur.execute(query, (address_key, latitude, longitude, datetime.now()))
        conn.commit()
        return True
    except Exception as e:
        print(f"Error inserting location for {address_key}: {e}")
        conn.rollback()
        return False


def main():
    """Main execution function."""
    print("="*60)
    print("Starting geocoding process...")
    print("="*60)
    
    # Initialize connections
    conn = get_db_connection()
    gmaps_client = get_gmaps_client()
    
    # Fetch addresses needing geocoding
    print("\nFetching Rank 1 (latest) listings missing from cache...")
    addresses = fetch_missing_addresses(conn)
    
    if not addresses:
        print("✓ All active listings are already geocoded!")
        conn.close()
        return
    
    print(f"Found {len(addresses)} addresses to geocode.\n")
    
    # Geocode and insert each address
    success_count = 0
    fail_count = 0
    
    for i, address_key in enumerate(addresses, 1):
        print(f"[{i}/{len(addresses)}] Processing: {address_key}")
        
        lat, lng = geocode_address(gmaps_client, address_key)
        
        if lat is not None and lng is not None:
            if insert_location(conn, address_key, lat, lng):
                success_count += 1
                print(f"  ✓ Cached: ({lat:.6f}, {lng:.6f})")
            else:
                fail_count += 1
                print(f"  ✗ Failed to cache in database")
        else:
            fail_count += 1
            print(f"  ✗ Failed to geocode")
        
        # Rate limiting: sleep briefly between requests
        if i < len(addresses):
            time.sleep(0.1)
    
    # Summary
    print("\n" + "="*60)
    print("GEOCODING COMPLETE")
    print("="*60)
    print(f"Successfully geocoded and cached: {success_count}")
    print(f"Failed: {fail_count}")
    print(f"Total processed: {len(addresses)}")
    print("="*60)
    
    conn.close()


if __name__ == "__main__":
    main()
