-- ============================================================
-- Update unified_listings_vw to Extract Contact Information
-- ============================================================
-- This script adds a dedicated `contact` column to the unified_listings_vw
-- Extracts phone numbers from various fields and formats them consistently
-- 
-- DEPENDENCIES:
--   - This will CASCADE and drop public.map_listings_geojson
--   - You must recreate map_listings_geojson after running this
--
-- INSTRUCTIONS:
--   1. Run Step 1 to drop the existing view (CASCADE drops dependent views)
--   2. Run Step 2 to recreate unified_listings_vw with contact extraction
--   3. Run Step 3 to recreate map_listings_geojson view
--   4. Run Step 4 to verify the changes
-- ============================================================

-- ============================================================
-- STEP 1: Drop Existing View (CASCADE to dependent views)
-- ============================================================
DROP VIEW IF EXISTS marts.unified_listings_vw CASCADE;

-- ============================================================
-- STEP 2: Recreate unified_listings_vw with Contact Extraction
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
  -- NEW: Contact field with symbol cleanup
  -- Extracts from contact field or URL (if URL contains phone)
  -- Removes trailing symbols like ©, ®, (L)
  TRIM(
    regexp_replace(
      COALESCE(
        solil_listings_vw.contact,
        CASE 
          WHEN solil_listings_vw.url ~ '\(?[0-9]{3}\)?[-.\s]*[0-9]{3}[-.\s]*[0-9]{4}' 
          THEN solil_listings_vw.url
          ELSE NULL
        END
      ),
      '\s*[©®]\s*|\s*\([A-Z]\)\s*$',
      '',
      'gi'
    )
  ) AS contact,
  -- Updated description_combined (contact removed since now separate column)
  concat_ws(
    ' | '::text,
    'Addl Info: '::text || solil_listings_vw.add_i,
    'Super: '::text || solil_listings_vw.super,
    'URL: '::text || CASE 
      WHEN solil_listings_vw.url ~ '\(?[0-9]{3}\)?[-.\s]*[0-9]{3}[-.\s]*[0-9]{4}'
      THEN NULL  -- Don't show phone number as URL
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
  'UWS'::text AS source_name,
  uws_listings_vw.id AS source_id,
  uws_listings_vw.address,
  uws_listings_vw.unit_num AS unit_number,
  uws_listings_vw.unit_size AS bedrooms,
  NULL::text AS bathrooms,
  uws_listings_vw.sq_ft AS square_feet,
  uws_listings_vw.rent_1yr AS rent_price,
  NULL::text AS listing_status,
  uws_listings_vw.ready_date AS available_date_raw,
  -- NEW: Extract contact from description field
  -- Handles multiple patterns including 10-digit and 7-digit phones
  -- Supports formats like: (XXX) XXX-XXXX, XXX-XXX-XXXX, XXX-XXXX
  CASE
    -- Pattern: "showings [Name]: [phone]"
    WHEN uws_listings_vw.description ~* 'showings?\s+([A-Za-z\s]+):\s*\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4})'
      THEN regexp_replace(
        uws_listings_vw.description,
        '.*showings?\s+([A-Za-z\s]+):\s*\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4}).*',
        '\1: \2-\3-\4',
        'i'
      )
    -- Pattern: "contact [Name/tenant] at [phone]" or "contact [Name] [phone]"
    WHEN uws_listings_vw.description ~* 'contact\s+([A-Za-z\s]+?)\s+(at\s+)?\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4})'
      THEN regexp_replace(
        uws_listings_vw.description,
        '.*contact\s+([A-Za-z\s]+?)\s+(at\s+)?\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4}).*',
        '\1: \3-\4-\5',
        'i'
      )
    -- Pattern: "call [Name] at [phone]"
    WHEN uws_listings_vw.description ~* 'call\s+([A-Za-z\s]+?)\s+at\s+\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4})'
      THEN regexp_replace(
        uws_listings_vw.description,
        '.*call\s+([A-Za-z\s]+?)\s+at\s+\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4}).*',
        '\1: \2-\3-\4',
        'i'
      )
    -- Pattern: "To View: [Name] [phone]"
    WHEN uws_listings_vw.description ~* 'To View:\s*([A-Za-z.\s]+?)\s+\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4})'
      THEN regexp_replace(
        uws_listings_vw.description,
        '.*To View:\s*([A-Za-z.\s]+?)\s+\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4}).*',
        '\1: \2-\3-\4',
        'i'
      )
    -- Pattern: "super [7-digit number]" or "super [name] [7-digit]"
    WHEN uws_listings_vw.description ~* 'super\s+([A-Za-z\s]*?)\s*([0-9]{3})[-.\s]*([0-9]{4})'
      THEN 'Super: ' || regexp_replace(
        uws_listings_vw.description,
        '.*super\s+([A-Za-z\s]*?)\s*([0-9]{3})[-.\s]*([0-9]{4}).*',
        '\2-\3',
        'i'
      )
    -- Fallback: Any 10-digit phone (with or without parentheses)
    WHEN uws_listings_vw.description ~ '\(?[0-9]{3}\)?[-.\s]*[0-9]{3}[-.\s]*[0-9]{4}'
      THEN
        (regexp_match(uws_listings_vw.description, '\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4})'))[1] || '-' ||
        (regexp_match(uws_listings_vw.description, '\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4})'))[2] || '-' ||
        (regexp_match(uws_listings_vw.description, '\(?([0-9]{3})\)?[-.\s]*([0-9]{3})[-.\s]*([0-9]{4})'))[3]
    -- Fallback: 7-digit phone (local number without area code)
    WHEN uws_listings_vw.description ~ '\b([0-9]{3})[-.\s]*([0-9]{4})\b'
      THEN
        (regexp_match(uws_listings_vw.description, '\b([0-9]{3})[-.\s]*([0-9]{4})\b'))[1] || '-' ||
        (regexp_match(uws_listings_vw.description, '\b([0-9]{3})[-.\s]*([0-9]{4})\b'))[2]
    ELSE NULL
  END AS contact,
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
-- STEP 3: Recreate public.map_listings_geojson with Contact
-- ============================================================
CREATE OR REPLACE VIEW public.map_listings_geojson AS
WITH ranked_listings AS (
    SELECT
        v.source_name,
        v.address,
        v.unit_number,
        v.rent_price,
        v.bedrooms,
        v.bathrooms,
        v.contact,  -- NEW: Include contact field
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
            'contact', l.contact,  -- NEW: Add contact to properties
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

-- Grant access for authenticated users
GRANT SELECT ON public.map_listings_geojson TO authenticated;

-- ============================================================
-- STEP 4: Verification Queries
-- ============================================================
-- Run these to verify the changes worked correctly

-- Check that contact column exists and is populated
SELECT 
  source_name, 
  address, 
  unit_number,
  contact, 
  LEFT(description_combined, 50) as description_preview
FROM marts.unified_listings_vw 
WHERE contact IS NOT NULL
LIMIT 20;

-- Verify map_listings_geojson includes contact in properties
SELECT 
  feature->'properties'->>'address' as address,
  feature->'properties'->>'contact' as contact,
  feature->'properties'->>'source' as source
FROM public.map_listings_geojson 
WHERE feature->'properties'->>'contact' IS NOT NULL
LIMIT 10;

-- Count listings with contacts by source
SELECT 
  source_name,
  COUNT(*) as total_listings,
  COUNT(contact) as listings_with_contact,
  ROUND(100.0 * COUNT(contact) / COUNT(*), 1) as percentage_with_contact
FROM marts.unified_listings_vw
GROUP BY source_name;

