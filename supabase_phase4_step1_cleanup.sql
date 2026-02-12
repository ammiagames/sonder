-- STEP 1: Cleanup existing policies
-- Run this FIRST, ignore any "does not exist" errors

DROP POLICY IF EXISTS "Users can view own follows" ON follows;
DROP POLICY IF EXISTS "Users can view their followers" ON follows;
DROP POLICY IF EXISTS "Users can follow others" ON follows;
DROP POLICY IF EXISTS "Users can unfollow" ON follows;
