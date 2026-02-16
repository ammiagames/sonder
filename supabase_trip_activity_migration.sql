-- Trip Activity Feed Migration
-- Tracks trip creation and log additions for feed activity subtitles

-- 1. Create table
CREATE TABLE trip_activity (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    activity_type TEXT NOT NULL CHECK (activity_type IN ('trip_created', 'log_added')),
    log_id UUID REFERENCES logs(id) ON DELETE CASCADE,
    place_name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- 2. Indexes
CREATE INDEX idx_trip_activity_trip_id ON trip_activity(trip_id);
CREATE INDEX idx_trip_activity_user_id ON trip_activity(user_id);

-- One trip_created per trip
CREATE UNIQUE INDEX idx_trip_activity_trip_created
    ON trip_activity(trip_id) WHERE activity_type = 'trip_created';

-- One log_added per log
CREATE UNIQUE INDEX idx_trip_activity_log_added
    ON trip_activity(log_id) WHERE activity_type = 'log_added';

-- 3. RLS
ALTER TABLE trip_activity ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read trip activities"
    ON trip_activity FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Users can insert own activities"
    ON trip_activity FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- 4. Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE trip_activity;

-- 5. Trigger: trip_created
CREATE OR REPLACE FUNCTION handle_trip_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO trip_activity (trip_id, user_id, activity_type)
    VALUES (NEW.id, NEW.created_by::uuid, 'trip_created')
    ON CONFLICT DO NOTHING;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_trip_created
    AFTER INSERT ON trips
    FOR EACH ROW
    EXECUTE FUNCTION handle_trip_created();

-- 6. Trigger: log added to trip (INSERT)
CREATE OR REPLACE FUNCTION handle_log_trip_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_place_name TEXT;
BEGIN
    IF NEW.trip_id IS NOT NULL THEN
        SELECT name INTO v_place_name FROM places WHERE id = NEW.place_id;

        INSERT INTO trip_activity (trip_id, user_id, activity_type, log_id, place_name)
        VALUES (NEW.trip_id, NEW.user_id::uuid, 'log_added', NEW.id, v_place_name)
        ON CONFLICT DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_log_trip_insert
    AFTER INSERT ON logs
    FOR EACH ROW
    EXECUTE FUNCTION handle_log_trip_insert();

-- 7. Trigger: log assigned to trip (UPDATE trip_id)
CREATE OR REPLACE FUNCTION handle_log_trip_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_place_name TEXT;
BEGIN
    IF NEW.trip_id IS NOT NULL AND (OLD.trip_id IS NULL OR OLD.trip_id != NEW.trip_id) THEN
        SELECT name INTO v_place_name FROM places WHERE id = NEW.place_id;

        INSERT INTO trip_activity (trip_id, user_id, activity_type, log_id, place_name)
        VALUES (NEW.trip_id, NEW.user_id::uuid, 'log_added', NEW.id, v_place_name)
        ON CONFLICT DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_log_trip_update
    AFTER UPDATE OF trip_id ON logs
    FOR EACH ROW
    EXECUTE FUNCTION handle_log_trip_update();
