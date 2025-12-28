-- PostgreSQL Initialization Script
-- Boulder Home Automation Historical Data Storage

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Create events table for all MQTT messages
CREATE TABLE IF NOT EXISTS events (
    id SERIAL PRIMARY KEY,
    event_id UUID DEFAULT uuid_generate_v4(),
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    source VARCHAR(255) NOT NULL,
    topic VARCHAR(500) NOT NULL,
    event_type VARCHAR(100),
    payload JSONB,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_event_id UNIQUE (event_id)
);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_events_source ON events(source);
CREATE INDEX IF NOT EXISTS idx_events_topic ON events(topic);
CREATE INDEX IF NOT EXISTS idx_events_event_type ON events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_payload ON events USING gin(payload);
CREATE INDEX IF NOT EXISTS idx_events_created_at ON events(created_at DESC);

-- Create Frigate detections table
CREATE TABLE IF NOT EXISTS frigate_detections (
    id SERIAL PRIMARY KEY,
    detection_id UUID DEFAULT uuid_generate_v4(),
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    camera_name VARCHAR(100) NOT NULL,
    object_type VARCHAR(50) NOT NULL,
    confidence FLOAT,
    zone VARCHAR(100),
    snapshot_url TEXT,
    bounding_box JSONB,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_frigate_timestamp ON frigate_detections(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_frigate_camera ON frigate_detections(camera_name);
CREATE INDEX IF NOT EXISTS idx_frigate_object ON frigate_detections(object_type);
CREATE INDEX IF NOT EXISTS idx_frigate_zone ON frigate_detections(zone);

-- Create camera state table
CREATE TABLE IF NOT EXISTS camera_state (
    id SERIAL PRIMARY KEY,
    camera_name VARCHAR(100) NOT NULL,
    state JSONB NOT NULL,
    last_motion TIMESTAMP WITH TIME ZONE,
    last_detection TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_camera UNIQUE (camera_name)
);

CREATE INDEX IF NOT EXISTS idx_camera_state_updated ON camera_state(updated_at DESC);

-- Create Abode alarm state table
CREATE TABLE IF NOT EXISTS abode_state (
    id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    mode VARCHAR(50) NOT NULL,
    devices JSONB,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_abode_timestamp ON abode_state(timestamp DESC);

-- Create automation executions table
CREATE TABLE IF NOT EXISTS automation_executions (
    id SERIAL PRIMARY KEY,
    execution_id UUID DEFAULT uuid_generate_v4(),
    automation_name VARCHAR(200) NOT NULL,
    trigger_source VARCHAR(100),
    trigger_data JSONB,
    result VARCHAR(50),
    error_message TEXT,
    duration_ms INTEGER,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_automation_started ON automation_executions(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_automation_name ON automation_executions(automation_name);
CREATE INDEX IF NOT EXISTS idx_automation_result ON automation_executions(result);

-- Create retention policy function (run daily)
CREATE OR REPLACE FUNCTION cleanup_old_data() RETURNS void AS $$
BEGIN
    -- Delete events older than 365 days
    DELETE FROM events WHERE created_at < NOW() - INTERVAL '365 days';
    
    -- Delete Frigate detections older than 90 days
    DELETE FROM frigate_detections WHERE created_at < NOW() - INTERVAL '90 days';
    
    -- Delete Abode state older than 365 days
    DELETE FROM abode_state WHERE created_at < NOW() - INTERVAL '365 days';
    
    -- Delete automation executions older than 180 days
    DELETE FROM automation_executions WHERE started_at < NOW() - INTERVAL '180 days';
    
    -- Vacuum tables to reclaim space
    VACUUM ANALYZE events;
    VACUUM ANALYZE frigate_detections;
    VACUUM ANALYZE abode_state;
    VACUUM ANALYZE automation_executions;
END;
$$ LANGUAGE plpgsql;

-- Create summary views for common queries
CREATE OR REPLACE VIEW daily_detection_summary AS
SELECT 
    DATE(timestamp) as date,
    camera_name,
    object_type,
    COUNT(*) as detection_count,
    AVG(confidence) as avg_confidence
FROM frigate_detections
WHERE timestamp > NOW() - INTERVAL '30 days'
GROUP BY DATE(timestamp), camera_name, object_type
ORDER BY date DESC, detection_count DESC;

CREATE OR REPLACE VIEW hourly_event_summary AS
SELECT 
    DATE_TRUNC('hour', timestamp) as hour,
    source,
    event_type,
    COUNT(*) as event_count
FROM events
WHERE timestamp > NOW() - INTERVAL '7 days'
GROUP BY DATE_TRUNC('hour', timestamp), source, event_type
ORDER BY hour DESC;

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO homeautomation;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO homeautomation;
GRANT EXECUTE ON FUNCTION cleanup_old_data() TO homeautomation;

-- Insert initial metadata
INSERT INTO events (source, topic, event_type, payload) VALUES 
    ('system', 'homeautomation/init', 'database_initialized', 
     '{"version": "1.0", "initialized_at": "' || NOW() || '"}'::jsonb)
ON CONFLICT DO NOTHING;