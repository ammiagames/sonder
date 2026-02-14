-- Trips & Trip Invitations - Supabase Migration
-- Run this in the Supabase SQL Editor

-- =====================================================
-- TRIPS TABLE
-- =====================================================

CREATE TABLE IF NOT EXISTS trips (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    cover_photo_url TEXT,
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ,
    collaborator_ids TEXT[] DEFAULT '{}',
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_trips_created_by ON trips(created_by);

ALTER TABLE trips ENABLE ROW LEVEL SECURITY;

-- Owner can do everything with their trips
CREATE POLICY "Users can view own trips"
    ON trips FOR SELECT
    USING (auth.uid() = created_by);

-- Collaborators can view trips they're part of
CREATE POLICY "Collaborators can view trips"
    ON trips FOR SELECT
    USING (auth.uid()::text = ANY(collaborator_ids));

CREATE POLICY "Users can create trips"
    ON trips FOR INSERT
    WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Users can update own trips"
    ON trips FOR UPDATE
    USING (auth.uid() = created_by);

CREATE POLICY "Users can delete own trips"
    ON trips FOR DELETE
    USING (auth.uid() = created_by);

-- =====================================================
-- TRIP INVITATIONS TABLE
-- =====================================================

CREATE TABLE IF NOT EXISTS trip_invitations (
    id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    inviter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    invitee_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(trip_id, invitee_id)
);

CREATE INDEX IF NOT EXISTS idx_trip_invitations_invitee ON trip_invitations(invitee_id);
CREATE INDEX IF NOT EXISTS idx_trip_invitations_trip ON trip_invitations(trip_id);

ALTER TABLE trip_invitations ENABLE ROW LEVEL SECURITY;

-- Invitee can view their invitations
CREATE POLICY "Users can view own invitations"
    ON trip_invitations FOR SELECT
    USING (auth.uid() = invitee_id);

-- Trip owner can view invitations for their trips
CREATE POLICY "Trip owners can view trip invitations"
    ON trip_invitations FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM trips
            WHERE trips.id = trip_invitations.trip_id
            AND trips.created_by = auth.uid()
        )
    );

-- Trip owner can create invitations
CREATE POLICY "Trip owners can invite"
    ON trip_invitations FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM trips
            WHERE trips.id = trip_invitations.trip_id
            AND trips.created_by = auth.uid()
        )
    );

-- Invitee can update their invitation (accept/decline)
CREATE POLICY "Invitees can respond to invitations"
    ON trip_invitations FOR UPDATE
    USING (auth.uid() = invitee_id);

-- Trip owner can delete invitations
CREATE POLICY "Trip owners can delete invitations"
    ON trip_invitations FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM trips
            WHERE trips.id = trip_invitations.trip_id
            AND trips.created_by = auth.uid()
        )
    );

-- =====================================================
-- ADD trip_id COLUMN TO LOGS (if not exists)
-- =====================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'logs' AND column_name = 'trip_id'
    ) THEN
        ALTER TABLE logs ADD COLUMN trip_id TEXT REFERENCES trips(id) ON DELETE SET NULL;
    END IF;
END
$$;

-- =====================================================
-- VERIFICATION
-- =====================================================

SELECT 'Trips migration complete!' as status;
