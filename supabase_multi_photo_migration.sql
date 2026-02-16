-- Multi-Photo Support Migration v6
-- Fixes type mismatches across BOTH logs and follows tables

-- ============================================
-- PART A: Disable RLS on both tables
-- ============================================
ALTER TABLE logs DISABLE ROW LEVEL SECURITY;
ALTER TABLE follows DISABLE ROW LEVEL SECURITY;

-- ============================================
-- PART B: Add photo_urls column + migrate data
-- ============================================
ALTER TABLE logs ADD COLUMN IF NOT EXISTS photo_urls JSONB DEFAULT '[]'::jsonb;

UPDATE logs
SET photo_urls = CASE
    WHEN photo_url IS NOT NULL THEN jsonb_build_array(photo_url)
    ELSE '[]'::jsonb
END
WHERE photo_urls = '[]'::jsonb;

-- ============================================
-- PART C: Drop ALL policies on both tables
-- ============================================
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN
        SELECT policyname FROM pg_policies WHERE tablename = 'logs'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON logs', pol.policyname);
    END LOOP;

    FOR pol IN
        SELECT policyname FROM pg_policies WHERE tablename = 'follows'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON follows', pol.policyname);
    END LOOP;
END $$;

-- ============================================
-- PART D: Recreate follows policies (all ::text casts)
-- ============================================
CREATE POLICY "Users can view own follows"
    ON follows FOR SELECT
    USING (auth.uid()::text = follower_id::text);

CREATE POLICY "Users can view their followers"
    ON follows FOR SELECT
    USING (auth.uid()::text = following_id::text);

CREATE POLICY "Users can follow others"
    ON follows FOR INSERT
    WITH CHECK (auth.uid()::text = follower_id::text);

CREATE POLICY "Users can unfollow"
    ON follows FOR DELETE
    USING (auth.uid()::text = follower_id::text);

-- ============================================
-- PART E: Recreate logs policies (all ::text casts)
-- ============================================
CREATE POLICY "Users can view followed users logs"
    ON logs FOR SELECT
    USING (
        auth.uid()::text = user_id::text
        OR EXISTS (
            SELECT 1 FROM follows
            WHERE follows.follower_id::text = auth.uid()::text
              AND follows.following_id::text = logs.user_id::text
        )
    );

CREATE POLICY "Users can insert own logs"
    ON logs FOR INSERT
    WITH CHECK (auth.uid()::text = user_id::text);

CREATE POLICY "Users can update own logs"
    ON logs FOR UPDATE
    USING (auth.uid()::text = user_id::text);

CREATE POLICY "Users can delete own logs"
    ON logs FOR DELETE
    USING (auth.uid()::text = user_id::text);

-- ============================================
-- PART F: Re-enable RLS on both tables
-- ============================================
ALTER TABLE follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE logs ENABLE ROW LEVEL SECURITY;
