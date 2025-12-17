-- ============================================================
-- Supabase Security Setup - Row Level Security (RLS) Policies
-- ============================================================
-- Run this SQL in your Supabase SQL Editor to enable authentication
-- and restrict data access to logged-in users only
-- ============================================================

-- 1. Enable RLS on the locations cache table
ALTER TABLE public.locations_cache ENABLE ROW LEVEL SECURITY;

-- 2. Drop any existing permissive policies (if they exist)
DROP POLICY IF EXISTS "Allow read access for authenticated users only" ON public.locations_cache;
DROP POLICY IF EXISTS "authenticated_read_only" ON public.locations_cache;

-- 3. Create strict policy: Only authenticated users can read
CREATE POLICY "authenticated_read_only"
ON public.locations_cache
FOR SELECT
TO authenticated
USING (true);

-- 4. Revoke anonymous access (CRITICAL - this prevents unauthenticated access)
REVOKE SELECT ON public.locations_cache FROM anon;

-- 5. Secure the GeoJSON view
-- Views inherit RLS from their source tables, but we explicitly secure access
REVOKE SELECT ON public.map_listings_geojson FROM anon;
GRANT SELECT ON public.map_listings_geojson TO authenticated;

-- 6. Verify the policies are active
SELECT 
    schemaname,
    tablename,
    policyname,
    roles,
    cmd,
    qual
FROM pg_policies
WHERE tablename = 'locations_cache';

-- Expected output: Should show 'authenticated_read_only' policy for authenticated role

-- ============================================================
-- TESTING THE SECURITY
-- ============================================================
-- After running this SQL, test by querying as anonymous:
-- The query below should return 0 rows when run without authentication:
-- SELECT COUNT(*) FROM public.locations_cache;
-- 
-- If you're in the Supabase SQL Editor (authenticated), it will show results.
-- But the JavaScript API using the anon key will get 0 rows until users log in.
-- ============================================================

