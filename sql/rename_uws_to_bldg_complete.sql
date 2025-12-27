-- ============================================================
-- RENAME SOURCE: UWS to BLDG - Complete Schema Update
-- ============================================================
-- Purpose: Change source name from 'UWS' to 'BLDG' across all views and functions
-- 
-- This script performs a complete schema restructuring to rename the UWS
-- source to BLDG while preserving all functionality, permissions, and data.
--
-- WHAT THIS DOES:
-- 1. Drops and recreates views (CASCADE handles dependencies safely)
-- 2. Drops and recreates the listing_changes_by_source function
-- 3. Updates unified_listings_vw to use 'BLDG' instead of 'UWS'
-- 4. Uses actual bedrooms/bathrooms fields from uws_listings_vw (cast to text)
-- 5. Includes contact extraction (contact, contact_name, keys_access)
-- 6. Restores ALL original permissions exactly as they were
--
-- DEPENDENCIES:
-- - marts.solil_listings_vw (must exist)
-- - marts.uws_listings_vw (must exist with bedrooms and bathrooms fields)
-- - public.locations_cache (must exist with address_key)
--
-- PERMISSIONS RESTORED:
-- - public.map_listings_geojson: ALL to anon, authenticated, service_role
-- - marts.unified_listings_vw: SELECT to anon, authenticated, service_role
-- - marts.listing_changes_by_source(): PUBLIC EXECUTE
--
-- IMPORTANT NOTES:
-- - The underlying marts.uws_listings_vw keeps its name (no breaking changes)
-- - Only the display source_name changes from 'UWS' to 'BLDG'
-- - User visited units marked as 'UWS' won't match new 'BLDG' records
-- - Frontend filters will automatically update (data-driven)
-- - Make.com webhooks require no changes (pass-through function)
--
-- INSTRUCTIONS:
-- 1. Open Supabase SQL Editor
-- 2. Copy and paste this entire script
-- 3. Click "Run" to execute
-- 4. Review verification query results at the end
-- 5. Refresh your map page to see 'BLDG' in source filter
--
-- AUTHOR: AI Assistant
-- DATE: 2025-01-XX
-- VERSION: 1.0 (Final with bedrooms/bathrooms casting)
-- ============================================================

-- ============================================================
-- STEP 1: Drop Existing Views
-- ============================================================
DROP VIEW IF EXISTS public.map_listings_geojson CASCADE;
DROP VIEW IF EXISTS public.unified_listings_vw CASCADE;
DROP VIEW IF EXISTS marts.unified_listings_vw CASCADE;

-- ============================================================
-- STEP 2: Drop and Recreate Function (marts schema)
-- ============================================================
DROP FUNCTION IF EXISTS marts.listing_changes_by_source() CASCADE;

CREATE OR REPLACE FUNCTION marts.listing_changes_by_source()
RETURNS TABLE (
  address text,
  unit_number text,
  source_name text,
  change_type text,
  record_source_file text,
  compared_to_file text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH ranked_listings AS (
    SELECT
      v.source_name,
      v.address,
      v.unit_number,
      v.filename,
      v.filename_date,
      v.created_at,
      DENSE_RANK() OVER(PARTITION BY v.source_name ORDER BY v.filename_date DESC) as date_rank
    FROM
      marts.unified_listings_vw v
  ),
  
  -- FILTER: Only process sources updated TODAY
  active_sources_today AS (
    SELECT DISTINCT rl.source_name
    FROM ranked_listings rl
    WHERE rl.date_rank = 1 
    AND (rl.created_at AT TIME ZONE 'America/New_York')::date = (NOW() AT TIME ZONE 'America/New_York')::date
  ),
  
  latest_records AS (
    SELECT * FROM ranked_listings rl
    WHERE rl.date_rank = 1
    AND rl.source_name IN (SELECT ast.source_name FROM active_sources_today ast)
  ),
  
  previous_records AS (
    SELECT * FROM ranked_listings rl
    WHERE rl.date_rank = 2
    AND rl.source_name IN (SELECT ast.source_name FROM active_sources_today ast)
  ),
  
  batch_filenames AS (
    SELECT 
      rl.source_name,
      MAX(CASE WHEN rl.date_rank = 1 THEN rl.filename END) as latest_filename,
      MAX(CASE WHEN rl.date_rank = 2 THEN rl.filename END) as previous_filename
    FROM ranked_listings rl
    GROUP BY rl.source_name
  )

  -- Step 2: Find REMOVALS
  SELECT
    p.address,
    p.unit_number,
    p.source_name,
    'removal'::text AS change_type,
    p.filename AS record_source_file,
    f.latest_filename AS compared_to_file
  FROM
    previous_records AS p
  LEFT JOIN
    latest_records AS l
  ON
    p.source_name = l.source_name
    AND p.address = l.address
    AND p.unit_number = l.unit_number
  LEFT JOIN 
    batch_filenames f ON p.source_name = f.source_name 
  WHERE
    l.address IS NULL

  UNION ALL

  -- Step 3: Find ADDITIONS
  SELECT
    l.address,
    l.unit_number,
    l.source_name,
    'addition'::text AS change_type,
    l.filename AS record_source_file,
    f.previous_filename AS compared_to_file
  FROM
    latest_records AS l
  LEFT JOIN
    previous_records AS p
  ON
    l.source_name = p.source_name
    AND l.address = p.address
    AND l.unit_number = p.unit_number
  LEFT JOIN 
    batch_filenames f ON l.source_name = f.source_name 
  WHERE
    p.address IS NULL;
END;
$$;

-- ============================================================
-- STEP 3: Recreate marts.unified_listings_vw with BLDG
-- ============================================================
CREATE VIEW marts.unified_listings_vw AS
SELECT
  'Solil'::text AS source_name,
  solil_listings_vw.id AS source_id,
  solil_listings_vw.address,
  solil_listings_vw.apt AS unit_number,
  solil_listings_vw.bed AS bedrooms,
  solil_listings_vw.bath AS bathrooms,
  NULL::text AS square_feet,
  solil_listings_vw.ask_rent AS rent_price,
  solil_listings_vw.status AS listing_status,
  solil_listings_vw.moveout_date AS available_date_raw,
  -- Contact extraction with symbol cleanup
  TRIM(
    BOTH FROM
    regexp_replace(
      COALESCE(
        solil_listings_vw.contact,
        CASE 
          WHEN solil_listings_vw.url ~ '\(?[0-9]{3}\)?[-.\s]*[0-9]{3}[-.\s]*[0-9]{4}'::text 
          THEN solil_listings_vw.url
          ELSE NULL::text
        END
      ),
      '\s*[©®]\s*|\s*\([A-Z]\)\s*$'::text,
      ''::text,
      'gi'::text
    )
  ) AS contact,
  solil_listings_vw.super AS contact_name,
  NULL::text AS keys_access,
  concat_ws(
    ' | '::text,
    'Addl Info: '::text || solil_listings_vw.add_i,
    'Super: '::text || solil_listings_vw.super,
    'URL: '::text || CASE 
      WHEN solil_listings_vw.url ~ '\(?[0-9]{3}\)?[-.\s]*[0-9]{3}[-.\s]*[0-9]{4}'::text
      THEN NULL::text
      ELSE solil_listings_vw.url
    END
  ) AS description_combined,
  solil_listings_vw.filename,
  solil_listings_vw.filename_date,
  solil_listings_vw.created_at
FROM
  marts.solil_listings_vw

UNION ALL

SELECT
  'BLDG'::text AS source_name,  -- *** CHANGED FROM 'UWS' ***
  uws_listings_vw.id AS source_id,
  uws_listings_vw.address,
  uws_listings_vw.unit_num AS unit_number,
  uws_listings_vw.bedrooms::text AS bedrooms,  -- *** CAST numeric to text for UNION compatibility ***
  uws_listings_vw.bathrooms::text AS bathrooms,  -- *** CAST numeric to text for UNION compatibility ***
  uws_listings_vw.sq_ft AS square_feet,
  uws_listings_vw.rent_1yr AS rent_price,
  NULL::text AS listing_status,
  uws_listings_vw.ready_date AS available_date_raw,
  -- Contact extraction: Handles multiple phone number patterns
  CASE
    WHEN uws_listings_vw.description ~* 'showings?\s+([A-Za-z\s]+):\s*\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4})'::text 
      THEN regexp_replace(uws_listings_vw.description, '.*showings?\s+([A-Za-z\s]+):\s*\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4}).*'::text, '\1: \2-\3-\4'::text, 'i'::text)
    WHEN uws_listings_vw.description ~* 'contact\s+([A-Za-z\s]+?)\s+(at\s+)?\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4})'::text 
      THEN regexp_replace(uws_listings_vw.description, '.*contact\s+([A-Za-z\s]+?)\s+(at\s+)?\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4}).*'::text, '\1: \3-\4-\5'::text, 'i'::text)
    WHEN uws_listings_vw.description ~* 'call\s+([A-Za-z\s]+?)\s+at\s+\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4})'::text 
      THEN regexp_replace(uws_listings_vw.description, '.*call\s+([A-Za-z\s]+?)\s+at\s+\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4}).*'::text, '\1: \2-\3-\4'::text, 'i'::text)
    WHEN uws_listings_vw.description ~* 'To View:\s*([A-Za-z.\s]+?)\s+\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4})'::text 
      THEN regexp_replace(uws_listings_vw.description, '.*To View:\s*([A-Za-z.\s]+?)\s+\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4}).*'::text, '\1: \2-\3-\4'::text, 'i'::text)
    WHEN uws_listings_vw.description ~* 'super\s+([A-Za-z\s]*?)\s*([0-9]{3})[-.\s]*([0-9]{4})'::text 
      THEN 'Super: '::text || regexp_replace(uws_listings_vw.description, '.*super\s+([A-Za-z\s]*?)\s*([0-9]{3})[-.\s]*([0-9]{4}).*'::text, '\2-\3'::text, 'i'::text)
    WHEN uws_listings_vw.description ~ '\(?[0-9]{3}\)?[-.\s]*[0-9]{3}[-.\s]*[0-9]{4}'::text 
      THEN
        (regexp_match(uws_listings_vw.description, '\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4})'::text))[1] || '-'::text ||
        (regexp_match(uws_listings_vw.description, '\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4})'::text))[2] || '-'::text ||
        (regexp_match(uws_listings_vw.description, '\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4})'::text))[3]
    WHEN uws_listings_vw.description ~ '\b([0-9]{3})[-.\s]*([0-9]{4})\b'::text 
      THEN
        (regexp_match(uws_listings_vw.description, '\b([0-9]{3})[-.\s]*([0-9]{4})\b'::text))[1] || '-'::text ||
        (regexp_match(uws_listings_vw.description, '\b([0-9]{3})[-.\s]*([0-9]{4})\b'::text))[2]
    ELSE NULL::text
  END AS contact,
  -- Contact name extraction
  CASE
    WHEN uws_listings_vw.description ~* 'Keys with Superintendent\s+([A-Za-z\s]+?)(?:\s+[0-9]|$)'::text 
      THEN regexp_replace(uws_listings_vw.description, '.*Keys with Superintendent\s+([A-Za-z\s]+?)(?:\s+[0-9]|$).*'::text, '\1'::text, 'i'::text)
    WHEN uws_listings_vw.description ~* 'Keys with Super\s+([A-Za-z\s]+?)(?:\s+[0-9]|$)'::text 
      THEN regexp_replace(uws_listings_vw.description, '.*Keys with Super\s+([A-Za-z\s]+?)(?:\s+[0-9]|$).*'::text, '\1'::text, 'i'::text)
    WHEN uws_listings_vw.description ~* 'Keys with Handyman\s+([A-Za-z\s]+?)(?:\s+[0-9]|\.|$)'::text 
      THEN 'Handyman'::text
    WHEN uws_listings_vw.description ~* 'Keys with (the )?doorman'::text 
      THEN 'Doorman'::text
    WHEN uws_listings_vw.description ~* 'showings?\s+([A-Za-z\s]+):'::text 
      THEN regexp_replace(uws_listings_vw.description, '.*showings?\s+([A-Za-z\s]+):.*'::text, '\1'::text, 'i'::text)
    ELSE NULL::text
  END AS contact_name,
  -- Keys access extraction
  CASE
    WHEN uws_listings_vw.description ~* 'Keys with [^.|]+'::text 
      THEN TRIM(BOTH FROM regexp_replace(uws_listings_vw.description, '.*?(Keys with [^.|]+).*'::text, '\1'::text, 'i'::text))
    WHEN uws_listings_vw.description ~* 'KEYBOX\s+[0-9]+'::text 
      THEN 'Keybox '::text || (regexp_match(uws_listings_vw.description, 'KEYBOX\s+([0-9]+)'::text))[1]
    ELSE NULL::text
  END AS keys_access,
  concat_ws(
    ' | '::text,
    uws_listings_vw.description,
    'Improvements: '::text || uws_listings_vw.improvements,
    'Rent 2yr: '::text || uws_listings_vw.rent_2yr,
    'Rooms: '::text || uws_listings_vw.rooms
  ) AS description_combined,
  uws_listings_vw.filename,
  uws_listings_vw.filename_date,
  uws_listings_vw.created_at
FROM
  marts.uws_listings_vw;

-- ============================================================
-- STEP 4: Recreate public.map_listings_geojson
-- ============================================================
CREATE VIEW public.map_listings_geojson AS
WITH
  ranked_listings AS (
    SELECT
      v.source_name,
      v.address,
      v.unit_number,
      v.rent_price,
      v.bedrooms,
      v.bathrooms,
      v.contact,
      v.contact_name,
      v.keys_access,
      DENSE_RANK() OVER (
        PARTITION BY v.source_name
        ORDER BY v.filename_date DESC
      ) AS date_rank
    FROM
      marts.unified_listings_vw v
    WHERE
      v.unit_number IS NOT NULL
  ),
  latest_records AS (
    SELECT
      ranked_listings.source_name,
      ranked_listings.address,
      ranked_listings.unit_number,
      ranked_listings.rent_price,
      ranked_listings.bedrooms,
      ranked_listings.bathrooms,
      ranked_listings.contact,
      ranked_listings.contact_name,
      ranked_listings.keys_access,
      ranked_listings.date_rank
    FROM
      ranked_listings
    WHERE
      ranked_listings.date_rank = 1
  ),
  previous_records AS (
    SELECT
      ranked_listings.source_name,
      ranked_listings.address,
      ranked_listings.unit_number,
      ranked_listings.date_rank
    FROM
      ranked_listings
    WHERE
      ranked_listings.date_rank = 2
  )
SELECT
  l.source_name,
  l.address,
  l.unit_number,
  CASE
    WHEN p.address IS NULL THEN 'addition'::text
    ELSE 'existing'::text
  END AS status,
  jsonb_build_object(
    'type',
    'Feature',
    'geometry',
    jsonb_build_object(
      'type',
      'Point',
      'coordinates',
      jsonb_build_array(loc.longitude, loc.latitude)
    ),
    'properties',
    jsonb_build_object(
      'address',
      l.address,
      'unit',
      l.unit_number,
      'rent',
      l.rent_price,
      'bed',
      l.bedrooms,
      'bath',
      l.bathrooms,
      'source',
      l.source_name,
      'contact',
      l.contact,
      'contactName',
      l.contact_name,
      'keysAccess',
      l.keys_access,
      'status',
      CASE
        WHEN p.address IS NULL THEN 'addition'::text
        ELSE 'existing'::text
      END
    )
  ) AS feature
FROM
  latest_records l
  LEFT JOIN previous_records p ON l.source_name = p.source_name
  AND l.address = p.address
  AND NOT l.unit_number IS DISTINCT FROM p.unit_number
  JOIN locations_cache loc ON UPPER(
    TRIM(BOTH FROM l.address)
  ) = loc.address_key;

-- ============================================================
-- STEP 5: Restore All Permissions (EXACT MATCH)
-- ============================================================

-- Restore ALL permissions on public.map_listings_geojson
GRANT ALL ON public.map_listings_geojson TO anon;
GRANT ALL ON public.map_listings_geojson TO authenticated;
GRANT ALL ON public.map_listings_geojson TO service_role;

-- Restore SELECT permissions on marts.unified_listings_vw
GRANT SELECT ON marts.unified_listings_vw TO anon;
GRANT SELECT ON marts.unified_listings_vw TO authenticated;
GRANT SELECT ON marts.unified_listings_vw TO service_role;

-- Restore PUBLIC EXECUTE permission on function (marts schema)
GRANT EXECUTE ON FUNCTION marts.listing_changes_by_source() TO PUBLIC;

-- ============================================================
-- STEP 6: Verification Queries
-- ============================================================

-- 1. Verify source name changed to BLDG
SELECT DISTINCT source_name 
FROM marts.unified_listings_vw
ORDER BY source_name;

-- 2. Test the function still works
SELECT * FROM marts.listing_changes_by_source() LIMIT 5;

-- 3. Verify map view with all fields
SELECT 
  feature->'properties'->>'source' as source,
  COUNT(*) as count
FROM public.map_listings_geojson 
GROUP BY feature->'properties'->>'source'
ORDER BY source;

-- 4. Confirm BLDG listings now have bedrooms and bathrooms
SELECT 
  source_name,
  address,
  unit_number,
  bedrooms,
  bathrooms,
  rent_price
FROM marts.unified_listings_vw 
WHERE source_name = 'BLDG'
  AND (bedrooms IS NOT NULL OR bathrooms IS NOT NULL)
LIMIT 10;

-- 5. Verify bedrooms/bathrooms in map GeoJSON for BLDG
SELECT 
  feature->'properties'->>'address' as address,
  feature->'properties'->>'unit' as unit,
  feature->'properties'->>'bed' as bedrooms,
  feature->'properties'->>'bath' as bathrooms,
  feature->'properties'->>'source' as source
FROM public.map_listings_geojson 
WHERE feature->'properties'->>'source' = 'BLDG'
LIMIT 10;

-- 6. Verify permissions are restored correctly
SELECT 'VIEW: map_listings_geojson' as object, grantee, privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public' AND table_name = 'map_listings_geojson'
UNION ALL
SELECT 'VIEW: unified_listings_vw', grantee, privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'marts' AND table_name = 'unified_listings_vw'
UNION ALL
SELECT 'FUNCTION: listing_changes_by_source', grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'marts' AND routine_name = 'listing_changes_by_source'
ORDER BY object, grantee;

-- ============================================================
-- END OF SCRIPT
-- ============================================================
-- Expected Results:
-- - Query 1: Should show 'BLDG' and 'Solil'
-- - Query 2: Should return recent additions/removals (if any today)
-- - Query 3: Should show counts for both 'BLDG' and 'Solil'
-- - Query 4: Should show BLDG listings with bedroom/bathroom data
-- - Query 5: Should show BLDG properties in GeoJSON with bed/bath
-- - Query 6: Should show all permissions match original state
--
-- After successful execution:
-- 1. Refresh your map page
-- 2. Check the source filter dropdown - should show 'BLDG' not 'UWS'
-- 3. Make.com webhook should work without any changes
-- 4. All existing functionality preserved
-- ============================================================

