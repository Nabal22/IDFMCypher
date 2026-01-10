-- PostgreSQL IDFM Complete Setup Script
-- Deletes existing database, creates new one with correct structure, and imports data
-- Run with: psql -d postgres -f postgres-full-setup.sql

-- Drop and recreate database
DROP DATABASE IF EXISTS idfm_transport;
CREATE DATABASE idfm_transport;

\c idfm_transport

-- Create tables

CREATE TABLE agency (
    agency_id TEXT PRIMARY KEY,
    agency_name TEXT NOT NULL,
    agency_url TEXT,
    agency_timezone TEXT,
    agency_fare_url TEXT
);

CREATE TABLE routes (
    route_id TEXT PRIMARY KEY,
    agency_id TEXT,
    route_short_name TEXT,
    route_long_name TEXT,
    route_type INTEGER,
    route_color TEXT,
    route_text_color TEXT
);

CREATE TABLE stops (
    stop_id TEXT PRIMARY KEY,
    stop_code TEXT,
    stop_name TEXT NOT NULL,
    stop_lat DOUBLE PRECISION,
    stop_lon DOUBLE PRECISION,
    location_type INTEGER,
    parent_station TEXT,
    wheelchair_boarding INTEGER,
    level_id TEXT,
    platform_code TEXT
);

CREATE TABLE trips (
    route_id TEXT,
    service_id TEXT,
    trip_id TEXT PRIMARY KEY,
    trip_headsign TEXT,
    trip_short_name TEXT,
    direction_id INTEGER,
    wheelchair_accessible INTEGER,
    bikes_allowed INTEGER
);

CREATE TABLE stop_times (
    trip_id TEXT,
    arrival_time TEXT,
    departure_time TEXT,
    stop_id TEXT,
    stop_sequence INTEGER,
    stop_headsign TEXT,
    pickup_type INTEGER,
    drop_off_type INTEGER,
    timepoint INTEGER,
    PRIMARY KEY (trip_id, stop_sequence)
);

CREATE TABLE transfers (
    from_stop_id TEXT,
    to_stop_id TEXT,
    transfer_type INTEGER,
    min_transfer_time INTEGER,
    PRIMARY KEY (from_stop_id, to_stop_id)
);

CREATE TABLE pathways (
    pathway_id TEXT PRIMARY KEY,
    from_stop_id TEXT,
    to_stop_id TEXT,
    pathway_mode INTEGER,
    is_bidirectional INTEGER,
    length DOUBLE PRECISION,
    traversal_time INTEGER,
    stair_count INTEGER DEFAULT NULL,
    max_slope DOUBLE PRECISION DEFAULT NULL,
    min_width DOUBLE PRECISION DEFAULT NULL
);

CREATE TABLE calendar (
    service_id TEXT PRIMARY KEY,
    monday INTEGER,
    tuesday INTEGER,
    wednesday INTEGER,
    thursday INTEGER,
    friday INTEGER,
    saturday INTEGER,
    sunday INTEGER,
    start_date TEXT,
    end_date TEXT
);

CREATE TABLE calendar_dates (
    service_id TEXT,
    date TEXT,
    exception_type INTEGER,
    PRIMARY KEY (service_id, date)
);

-- Add foreign keys
ALTER TABLE routes ADD CONSTRAINT fk_routes_agency
    FOREIGN KEY (agency_id) REFERENCES agency(agency_id);

ALTER TABLE trips ADD CONSTRAINT fk_trips_route
    FOREIGN KEY (route_id) REFERENCES routes(route_id);

ALTER TABLE stop_times ADD CONSTRAINT fk_stop_times_trip
    FOREIGN KEY (trip_id) REFERENCES trips(trip_id);

ALTER TABLE stop_times ADD CONSTRAINT fk_stop_times_stop
    FOREIGN KEY (stop_id) REFERENCES stops(stop_id);

ALTER TABLE transfers ADD CONSTRAINT fk_transfers_from
    FOREIGN KEY (from_stop_id) REFERENCES stops(stop_id);

ALTER TABLE transfers ADD CONSTRAINT fk_transfers_to
    FOREIGN KEY (to_stop_id) REFERENCES stops(stop_id);

ALTER TABLE pathways ADD CONSTRAINT fk_pathways_from
    FOREIGN KEY (from_stop_id) REFERENCES stops(stop_id);

ALTER TABLE pathways ADD CONSTRAINT fk_pathways_to
    FOREIGN KEY (to_stop_id) REFERENCES stops(stop_id);

-- Add indexes
CREATE INDEX idx_stops_location ON stops(stop_lat, stop_lon);
CREATE INDEX idx_stop_times_stop ON stop_times(stop_id);
CREATE INDEX idx_stop_times_trip ON stop_times(trip_id);
CREATE INDEX idx_trips_route ON trips(route_id);
CREATE INDEX idx_transfers_from ON transfers(from_stop_id);
CREATE INDEX idx_transfers_to ON transfers(to_stop_id);
CREATE INDEX idx_pathways_from ON pathways(from_stop_id);
CREATE INDEX idx_pathways_to ON pathways(to_stop_id);

-- Add check constraints
ALTER TABLE stops ADD CHECK (wheelchair_boarding IN (0, 1, 2));
ALTER TABLE stops ADD CHECK (stop_lat BETWEEN -90 AND 90);
ALTER TABLE stops ADD CHECK (stop_lon BETWEEN -180 AND 180);
ALTER TABLE routes ADD CHECK (route_type >= 0);

\echo 'Database structure created.'
\echo ''
\echo 'Starting data import...'

-- Import data (order matters for foreign keys)
\echo 'Importing agency...'
\COPY agency FROM 'export/agency.csv' CSV HEADER;

\echo 'Importing calendar...'
\COPY calendar FROM 'export/calendar.csv' CSV HEADER;

\echo 'Importing calendar_dates...'
\COPY calendar_dates FROM 'export/calendar_dates.csv' CSV HEADER;

\echo 'Importing routes...'
\COPY routes FROM 'export/routes.csv' CSV HEADER;

\echo 'Importing stops...'
\COPY stops FROM 'export/stops.csv' CSV HEADER;

\echo 'Importing trips (subset)...'
\COPY trips FROM 'export/trips_subset.csv' CSV HEADER;

\echo 'Importing transfers...'
\COPY transfers FROM 'export/transfers.csv' CSV HEADER;

\echo 'Importing pathways (7 columns only)...'
\COPY pathways(pathway_id, from_stop_id, to_stop_id, pathway_mode, is_bidirectional, length, traversal_time) FROM 'export/pathways.csv' CSV HEADER;

\echo 'Importing stop_times (subset)...'
\COPY stop_times FROM 'export/stop_times_subset.csv' CSV HEADER;

\echo ''
\echo 'Import complete!'
\echo ''
\echo 'Verification:'

SELECT 'agency' as table_name, COUNT(*) as count FROM agency
UNION ALL SELECT 'routes', COUNT(*) FROM routes
UNION ALL SELECT 'stops', COUNT(*) FROM stops
UNION ALL SELECT 'trips', COUNT(*) FROM trips
UNION ALL SELECT 'stop_times', COUNT(*) FROM stop_times
UNION ALL SELECT 'transfers', COUNT(*) FROM transfers
UNION ALL SELECT 'pathways', COUNT(*) FROM pathways
UNION ALL SELECT 'calendar', COUNT(*) FROM calendar
UNION ALL SELECT 'calendar_dates', COUNT(*) FROM calendar_dates
ORDER BY table_name;

\echo ''
\echo 'Test query: Stops on metro lines'
SELECT DISTINCT s.stop_name
FROM stops s
JOIN stop_times st ON s.stop_id = st.stop_id
JOIN trips t ON st.trip_id = t.trip_id
JOIN routes r ON t.route_id = r.route_id
WHERE r.route_type = 1
LIMIT 5;

\echo ''
\echo 'PostgreSQL setup complete!'
