-- Phase 4: Social Layer - Supabase Migration
-- Run this in the Supabase SQL Editor

-- =====================================================
-- FOLLOWS TABLE
-- =====================================================

-- Create follows table (asymmetric follow model)
CREATE TABLE IF NOT EXISTS follows (
    follower_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    following_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    PRIMARY KEY (follower_id, following_id)
);

-- Indexes for efficient lookups
CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following ON follows(following_id);

-- Prevent self-follows
ALTER TABLE follows ADD CONSTRAINT no_self_follow CHECK (follower_id != following_id);

-- RLS Policies for follows
ALTER TABLE follows ENABLE ROW LEVEL SECURITY;

-- Users can see who they follow
CREATE POLICY "Users can view own follows"
    ON follows FOR SELECT
    USING (auth.uid() = follower_id);

-- Users can see who follows them
CREATE POLICY "Users can view their followers"
    ON follows FOR SELECT
    USING (auth.uid() = following_id);

-- Users can follow others
CREATE POLICY "Users can follow others"
    ON follows FOR INSERT
    WITH CHECK (auth.uid() = follower_id);

-- Users can unfollow
CREATE POLICY "Users can unfollow"
    ON follows FOR DELETE
    USING (auth.uid() = follower_id);


-- =====================================================
-- WANT TO GO TABLE
-- =====================================================

-- Create want_to_go table
CREATE TABLE IF NOT EXISTS want_to_go (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    place_id TEXT NOT NULL,
    source_log_id UUID REFERENCES logs(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(user_id, place_id)
);

-- Index for user lookups
CREATE INDEX IF NOT EXISTS idx_want_to_go_user ON want_to_go(user_id);

-- RLS Policies for want_to_go
ALTER TABLE want_to_go ENABLE ROW LEVEL SECURITY;

-- Users can only see their own want_to_go items
CREATE POLICY "Users can view own want_to_go"
    ON want_to_go FOR SELECT
    USING (auth.uid() = user_id);

-- Users can add to their own want_to_go
CREATE POLICY "Users can add to want_to_go"
    ON want_to_go FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own want_to_go
CREATE POLICY "Users can update own want_to_go"
    ON want_to_go FOR UPDATE
    USING (auth.uid() = user_id);

-- Users can remove from their own want_to_go
CREATE POLICY "Users can delete from want_to_go"
    ON want_to_go FOR DELETE
    USING (auth.uid() = user_id);


-- =====================================================
-- UPDATE LOGS RLS FOR FEED ACCESS
-- =====================================================

-- Allow viewing logs from followed users (for feed)
CREATE POLICY "Users can view followed users logs"
    ON logs FOR SELECT
    USING (
        -- Own logs
        auth.uid() = user_id
        OR
        -- Followed users' logs
        EXISTS (
            SELECT 1 FROM follows
            WHERE follows.follower_id = auth.uid()
            AND follows.following_id = logs.user_id
        )
        OR
        -- Public users' logs
        EXISTS (
            SELECT 1 FROM users
            WHERE users.id = logs.user_id
            AND users.is_public = true
        )
    );


-- =====================================================
-- UPDATE USERS RLS FOR PROFILE VIEWING
-- =====================================================

-- Allow viewing other users' profiles (for search/follow)
CREATE POLICY "Users can view other users profiles"
    ON users FOR SELECT
    USING (true);  -- All users are viewable (privacy controlled at log level)


-- =====================================================
-- FOREIGN KEY FOR PLACES IN WANT_TO_GO
-- =====================================================

-- Note: If places table exists and you want referential integrity:
-- ALTER TABLE want_to_go
--     ADD CONSTRAINT fk_want_to_go_place
--     FOREIGN KEY (place_id) REFERENCES places(id) ON DELETE CASCADE;

-- However, since place_id comes from Google Places API and may not always
-- exist in our places table first, we keep it as TEXT without foreign key.


-- =====================================================
-- VERIFICATION QUERIES
-- =====================================================

-- Run these to verify the setup:

-- Check tables exist
-- SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';

-- Check indexes
-- SELECT indexname FROM pg_indexes WHERE schemaname = 'public';

-- Check policies
-- SELECT policyname, tablename FROM pg_policies WHERE schemaname = 'public';
