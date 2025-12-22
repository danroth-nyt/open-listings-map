-- ============================================================
-- User Visited Units Tracking Table
-- ============================================================
-- This table stores which units each user has visited.
-- Visited status persists indefinitely until manually unmarked.
-- ============================================================

-- Create the table
CREATE TABLE IF NOT EXISTS public.user_visited_units (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    source_name TEXT NOT NULL,
    address TEXT NOT NULL,
    unit_number TEXT,
    visited_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Ensure each user can only mark a specific unit once
    UNIQUE(user_id, source_name, address, unit_number)
);

-- Add index for faster queries on user_id
CREATE INDEX IF NOT EXISTS idx_user_visited_units_user_id 
    ON public.user_visited_units(user_id);

-- Add index for date-based queries and sorting
CREATE INDEX IF NOT EXISTS idx_user_visited_units_visited_at 
    ON public.user_visited_units(visited_at);

-- Add partial unique index for rows with NULL unit_number
-- This prevents duplicate visited records when unit_number is NULL
-- (standard UNIQUE constraint treats each NULL as distinct)
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_visited_units_unique_no_unit
    ON public.user_visited_units(user_id, source_name, address)
    WHERE unit_number IS NULL;

-- ============================================================
-- Row Level Security (RLS) Policies
-- ============================================================
-- Users can only see and modify their own visited units
-- ============================================================

-- Enable Row Level Security
ALTER TABLE public.user_visited_units ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view their own visited units
CREATE POLICY "Users can view own visited units" 
    ON public.user_visited_units 
    FOR SELECT 
    USING (auth.uid() = user_id);

-- Policy: Users can insert their own visited units
CREATE POLICY "Users can insert own visited units" 
    ON public.user_visited_units 
    FOR INSERT 
    WITH CHECK (auth.uid() = user_id);

-- Policy: Users can delete their own visited units
CREATE POLICY "Users can delete own visited units" 
    ON public.user_visited_units 
    FOR DELETE 
    USING (auth.uid() = user_id);

-- ============================================================
-- Optional: Cleanup Function for Old Records
-- ============================================================
-- This function deletes records older than 6 months
-- OPTIONAL: Only use if you want to automatically clean up old visits
-- By default, visited status persists indefinitely
-- ============================================================

CREATE OR REPLACE FUNCTION cleanup_old_visited_units()
RETURNS void AS $$
BEGIN
    DELETE FROM public.user_visited_units
    WHERE visited_at < NOW() - INTERVAL '6 months';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- Instructions for Running This SQL
-- ============================================================
-- 1. Go to https://supabase.com/dashboard
-- 2. Select your project
-- 3. Navigate to SQL Editor
-- 4. Copy and paste this entire file
-- 5. Click "Run" to execute
-- ============================================================

