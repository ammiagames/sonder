-- Migration: Phone Auth + Invites System
-- Run this in the Supabase SQL Editor (Dashboard → SQL → New query)
--
-- Prerequisites:
--   1. Enable Phone Auth in Supabase Dashboard → Authentication → Providers → Phone
--   2. Configure Twilio: Account SID, Auth Token, Messaging Service SID
--   3. Set SMS template: "Your Sonder code is {{.Code}}"

-- 1. Invites table — tracks who invited whom (by phone hash for privacy)
CREATE TABLE IF NOT EXISTS invites (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    inviter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    invited_phone_hash TEXT NOT NULL,
    status TEXT DEFAULT 'sent',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(inviter_id, invited_phone_hash)  -- prevents duplicate invites to same person
);

-- RLS: users can only see their own invites
ALTER TABLE invites ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own invites"
    ON invites FOR SELECT
    USING (auth.uid() = inviter_id);

CREATE POLICY "Users can insert own invites"
    ON invites FOR INSERT
    WITH CHECK (auth.uid() = inviter_id);

-- 2. Add invite_count column to users table (lightweight migration)
ALTER TABLE users ADD COLUMN IF NOT EXISTS invite_count INTEGER DEFAULT 0;

-- 3. Atomic RPC: insert invite + update count, returns new count
--    Uses ON CONFLICT DO NOTHING to handle duplicate invites gracefully.
CREATE OR REPLACE FUNCTION record_invite(
    p_inviter_id UUID, p_phone_hash TEXT
) RETURNS INTEGER AS $$
DECLARE v_count INTEGER;
BEGIN
    INSERT INTO invites (inviter_id, invited_phone_hash)
    VALUES (p_inviter_id, p_phone_hash)
    ON CONFLICT (inviter_id, invited_phone_hash) DO NOTHING;

    SELECT COUNT(*) INTO v_count FROM invites WHERE inviter_id = p_inviter_id;
    UPDATE users SET invite_count = v_count WHERE id = p_inviter_id;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
