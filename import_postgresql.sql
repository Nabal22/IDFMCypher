-- ========================================
-- PostgreSQL Database Import Script
-- Dataset: US Flight Delays 2015 (Jan 1-7)
-- ========================================

-- Drop existing tables if they exist
DROP TABLE IF EXISTS flights CASCADE;
DROP TABLE IF EXISTS airports CASCADE;
DROP TABLE IF EXISTS airlines CASCADE;

-- ========================================
-- 1. Create Tables
-- ========================================

-- Airlines table
CREATE TABLE airlines (
    iata_code VARCHAR(2) PRIMARY KEY,
    name VARCHAR(100) NOT NULL
);

-- Airports table
CREATE TABLE airports (
    iata_code VARCHAR(3) PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state VARCHAR(2) NOT NULL,
    country VARCHAR(50) NOT NULL,
    latitude DECIMAL(10, 6) NOT NULL,
    longitude DECIMAL(10, 6) NOT NULL
);

-- Flights table
CREATE TABLE flights (
    id SERIAL PRIMARY KEY,
    source VARCHAR(3) NOT NULL,
    target VARCHAR(3) NOT NULL,
    airline VARCHAR(2) NOT NULL,
    departure_ts TIMESTAMP NOT NULL,
    arrival_ts TIMESTAMP NOT NULL,
    distance INTEGER NOT NULL,
    delay DECIMAL(10, 2),

    -- Foreign keys
    CONSTRAINT fk_source FOREIGN KEY (source) REFERENCES airports(iata_code),
    CONSTRAINT fk_target FOREIGN KEY (target) REFERENCES airports(iata_code),
    CONSTRAINT fk_airline FOREIGN KEY (airline) REFERENCES airlines(iata_code),

    -- Check constraints
    CONSTRAINT chk_different_airports CHECK (source != target),
    CONSTRAINT chk_positive_distance CHECK (distance > 0)
);

-- ========================================
-- 2. Import Data from CSV
-- ========================================

-- Note: Adjust the path to match your system
-- For Mac/Linux: use absolute paths like '/Users/...'
-- For Windows: use paths like 'C:/Users/...'

-- Import airlines
\COPY airlines(iata_code, name) FROM 'import/airlines.csv' WITH (FORMAT csv, HEADER true);

-- Import airports
\COPY airports(iata_code, name, city, state, country, latitude, longitude) FROM 'import/airports_projet.csv' WITH (FORMAT csv, HEADER true);

-- Import flights
\COPY flights(source, target, airline, departure_ts, arrival_ts, distance, delay) FROM 'import/flights_projet.csv' WITH (FORMAT csv, HEADER true);

-- ========================================
-- 3. Create Indexes for Performance
-- ========================================

-- Indexes on airports
CREATE INDEX idx_airports_city ON airports(city);
CREATE INDEX idx_airports_state ON airports(state);
CREATE INDEX idx_airports_location ON airports(latitude, longitude);

-- Indexes on flights
CREATE INDEX idx_flights_source ON flights(source);
CREATE INDEX idx_flights_target ON flights(target);
CREATE INDEX idx_flights_airline ON flights(airline);
CREATE INDEX idx_flights_departure_ts ON flights(departure_ts);
CREATE INDEX idx_flights_arrival_ts ON flights(arrival_ts);
CREATE INDEX idx_flights_delay ON flights(delay);
CREATE INDEX idx_flights_distance ON flights(distance);

-- Composite indexes for common queries
CREATE INDEX idx_flights_source_target ON flights(source, target);
CREATE INDEX idx_flights_departure_date ON flights(DATE(departure_ts));

-- ========================================
-- 4. Add Comments for Documentation
-- ========================================

COMMENT ON TABLE airlines IS 'US airline carriers';
COMMENT ON TABLE airports IS 'US airports with geographic information';
COMMENT ON TABLE flights IS 'Flight records for January 1-7, 2015';

COMMENT ON COLUMN flights.delay IS 'Departure delay in minutes (negative = early)';
COMMENT ON COLUMN flights.distance IS 'Flight distance in miles';
COMMENT ON COLUMN airports.latitude IS 'Airport latitude in decimal degrees';
COMMENT ON COLUMN airports.longitude IS 'Airport longitude in decimal degrees';

-- ========================================
-- 5. Create Views for Common Queries
-- ========================================

-- View: Flights with full airport and airline information
CREATE OR REPLACE VIEW flights_detailed AS
SELECT
    f.id,
    f.source,
    src.name AS source_name,
    src.city AS source_city,
    src.state AS source_state,
    f.target,
    dst.name AS target_name,
    dst.city AS target_city,
    dst.state AS target_state,
    f.airline,
    al.name AS airline_name,
    f.departure_ts,
    f.arrival_ts,
    f.arrival_ts - f.departure_ts AS duration,
    f.distance,
    f.delay
FROM flights f
JOIN airports src ON f.source = src.iata_code
JOIN airports dst ON f.target = dst.iata_code
JOIN airlines al ON f.airline = al.iata_code;

-- View: Airport statistics
CREATE OR REPLACE VIEW airport_stats AS
SELECT
    a.iata_code,
    a.name,
    a.city,
    a.state,
    COUNT(DISTINCT f_out.id) AS departures,
    COUNT(DISTINCT f_in.id) AS arrivals,
    COUNT(DISTINCT f_out.id) + COUNT(DISTINCT f_in.id) AS total_flights,
    AVG(f_out.delay) AS avg_departure_delay,
    COUNT(DISTINCT f_out.target) AS direct_destinations
FROM airports a
LEFT JOIN flights f_out ON a.iata_code = f_out.source
LEFT JOIN flights f_in ON a.iata_code = f_in.target
GROUP BY a.iata_code, a.name, a.city, a.state;

-- View: Airline statistics
CREATE OR REPLACE VIEW airline_stats AS
SELECT
    al.iata_code,
    al.name,
    COUNT(f.id) AS total_flights,
    AVG(f.delay) AS avg_delay,
    AVG(f.distance) AS avg_distance,
    COUNT(CASE WHEN f.delay > 0 THEN 1 END) AS delayed_flights,
    100.0 * COUNT(CASE WHEN f.delay > 0 THEN 1 END) / COUNT(f.id) AS delay_rate_pct
FROM airlines al
LEFT JOIN flights f ON al.iata_code = f.airline
GROUP BY al.iata_code, al.name;

-- ========================================
-- 6. Verification Queries
-- ========================================

-- Count records
SELECT 'Airlines' AS table_name, COUNT(*) AS count FROM airlines
UNION ALL
SELECT 'Airports', COUNT(*) FROM airports
UNION ALL
SELECT 'Flights', COUNT(*) FROM flights
ORDER BY table_name;

-- Sample data
SELECT * FROM flights_detailed LIMIT 10;

-- Top 10 hubs by total flights
SELECT
    iata_code,
    city,
    state,
    departures,
    arrivals,
    total_flights
FROM airport_stats
ORDER BY total_flights DESC
LIMIT 10;

-- Airline statistics
SELECT * FROM airline_stats
ORDER BY total_flights DESC;

-- Database size
SELECT
    pg_size_pretty(pg_database_size(current_database())) AS database_size;

-- Table sizes
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
