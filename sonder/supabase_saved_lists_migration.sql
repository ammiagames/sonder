-- Migration: Saved Lists Feature
-- Adds saved_lists table and list_id column to want_to_go

-- New table: saved_lists
CREATE TABLE IF NOT EXISTS saved_lists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    emoji TEXT NOT NULL DEFAULT '🔖',
    is_default BOOLEAN NOT NULL DEFAULT false,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    UNIQUE(user_id, name)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_saved_lists_user_id ON saved_lists(user_id);

-- RLS
ALTER TABLE saved_lists ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own lists"
    ON saved_lists FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own lists"
    ON saved_lists FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own lists"
    ON saved_lists FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own lists"
    ON saved_lists FOR DELETE
    USING (auth.uid() = user_id);

-- Modify want_to_go: add list_id column
ALTER TABLE want_to_go ADD COLUMN IF NOT EXISTS list_id UUID REFERENCES saved_lists(id) ON DELETE CASCADE;

-- Update unique constraint to include list_id
ALTER TABLE want_to_go DROP CONSTRAINT IF EXISTS want_to_go_user_id_place_id_key;
ALTER TABLE want_to_go ADD CONSTRAINT want_to_go_user_place_list_unique UNIQUE (user_id, place_id, list_id);

-- Index for list_id lookups
CREATE INDEX IF NOT EXISTS idx_want_to_go_list_id ON want_to_go(list_id);

-- Server-side migration: create default "Want to Go" list for each user
-- and backfill existing want_to_go rows with the default list_id
DO $$
DECLARE
    r RECORD;
    default_list_id UUID;
BEGIN
    FOR r IN SELECT DISTINCT user_id FROM want_to_go WHERE list_id IS NULL LOOP
        -- Create default list for this user (if not exists)
        INSERT INTO saved_lists (user_id, name, emoji, is_default, sort_order)
        VALUES (r.user_id, 'Want to Go', '🔖', true, 0)
        ON CONFLICT (user_id, name) DO NOTHING
        RETURNING id INTO default_list_id;

        -- If insert was a no-op (already exists), fetch the id
        IF default_list_id IS NULL THEN
            SELECT id INTO default_list_id
            FROM saved_lists
            WHERE user_id = r.user_id AND is_default = true
            LIMIT 1;
        END IF;

        -- Backfill want_to_go rows
        UPDATE want_to_go
        SET list_id = default_list_id
        WHERE user_id = r.user_id AND list_id IS NULL;
    END LOOP;
END $$;
