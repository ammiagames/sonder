-- Phase 4: Social Layer - SAFE Migration (idempotent)
-- Can be run multiple times without errors

-- =====================================================
-- CLEAN UP EXISTING POLICIES (if any)
-- =====================================================

DROP POLICY IF EXISTS "Users can view own follows" ON follows;
DROP POLICY IF EXISTS "Users can view their followers" ON follows;
DROP POLICY IF EXISTS "Users can follow others" ON follows;
DROP POLICY IF EXISTS "Users can unfollow" ON follows;

DROP POLICY IF EXISTS "Users can view own want_to_go" ON want_to_go;
DROP POLICY IF EXISTS "Users can add to want_to_go" ON want_to_go;
DROP POLICY IF EXISTS "Users can update own want_to_go" ON want_to_go;
DROP POLICY IF EXISTS "Users can delete from want_to_go" ON want_to_go;

DROP POLICY IF EXISTS "Users can view followed users logs" ON logs;
DROP POLICY IF EXISTS "Users can view other users profiles" ON users;


-- =====================================================
-- FOLLOWS TABLE
-- =====================================================

CREATE TABLE IF NOT EXISTS follows (
    follower_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    following_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    PRIMARY KEY (follower_id, following_id)
);

CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following ON follows(following_id);

-- Add constraint only if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'no_self_follow'
    ) THEN
        ALTER TABLE follows ADD CONSTRAINT no_self_follow CHECK (follower_id != following_id);
    END IF;
END $$;

ALTER TABLE follows ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own follows"
    ON follows FOR SELECT
    USING (auth.uid() = follower_id);

CREATE POLICY "Users can view their followers"
    ON follows FOR SELECT
    USING (auth.uid() = following_id);

CREATE POLICY "Users can follow others"
    ON follows FOR INSERT
    WITH CHECK (auth.uid() = follower_id);

CREATE POLICY "Users can unfollow"
    ON follows FOR DELETE
    USING (auth.uid() = follower_id);


-- =====================================================
-- WANT TO GO TABLE
-- =====================================================

CREATE TABLE IF NOT EXISTS want_to_go (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    place_id TEXT NOT NULL,
    source_log_id UUID REFERENCES logs(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(user_id, place_id)
);

CREATE INDEX IF NOT EXISTS idx_want_to_go_user ON want_to_go(user_id);

ALTER TABLE want_to_go ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own want_to_go"
    ON want_to_go FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can add to want_to_go"
    ON want_to_go FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own want_to_go"
    ON want_to_go FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete from want_to_go"
    ON want_to_go FOR DELETE
    USING (auth.uid() = user_id);


-- =====================================================
-- UPDATE LOGS RLS FOR FEED ACCESS
-- =====================================================

CREATE POLICY "Users can view followed users logs"
    ON logs FOR SELECT
    USING (
        auth.uid() = user_id
        OR
        EXISTS (
            SELECT 1 FROM follows
            WHERE follows.follower_id = auth.uid()
            AND follows.following_id = logs.user_id
        )
        OR
        EXISTS (
            SELECT 1 FROM users
            WHERE users.id = logs.user_id
            AND users.is_public = true
        )
    );


-- =====================================================
-- UPDATE USERS RLS FOR PROFILE VIEWING
-- =====================================================

CREATE POLICY "Users can view other users profiles"
    ON users FOR SELECT
    USING (true);


-- =====================================================
-- VERIFICATION
-- =====================================================

SELECT 'Migration complete!' as status;
