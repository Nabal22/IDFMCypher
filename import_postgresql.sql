-- PostgreSQL Import Script

DROP TABLE IF EXISTS flights CASCADE;
DROP TABLE IF EXISTS airports CASCADE;
DROP TABLE IF EXISTS airlines CASCADE;

-- Create tables

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


    CONSTRAINT fk_source FOREIGN KEY (source) REFERENCES airports(iata_code),
    CONSTRAINT fk_target FOREIGN KEY (target) REFERENCES airports(iata_code),
    CONSTRAINT fk_airline FOREIGN KEY (airline) REFERENCES airlines(iata_code),


    CONSTRAINT chk_different_airports CHECK (source != target),
    CONSTRAINT chk_positive_distance CHECK (distance > 0)
);

-- Import Data

\COPY airlines(iata_code, name) FROM 'import/airlines.csv' WITH (FORMAT csv, HEADER true);

\COPY airports(iata_code, name, city, state, country, latitude, longitude) FROM 'import/airports_projet.csv' WITH (FORMAT csv, HEADER true);

\COPY flights(source, target, airline, departure_ts, arrival_ts, distance, delay) FROM 'import/flights_projet.csv' WITH (FORMAT csv, HEADER true);

-- Create Indexes

-- airports
CREATE INDEX idx_airports_city ON airports(city);
CREATE INDEX idx_airports_state ON airports(state);
CREATE INDEX idx_airports_location ON airports(latitude, longitude);

-- flights
CREATE INDEX idx_flights_source ON flights(source);
CREATE INDEX idx_flights_target ON flights(target);
CREATE INDEX idx_flights_airline ON flights(airline);
CREATE INDEX idx_flights_departure_ts ON flights(departure_ts);
CREATE INDEX idx_flights_arrival_ts ON flights(arrival_ts);
CREATE INDEX idx_flights_delay ON flights(delay);
CREATE INDEX idx_flights_distance ON flights(distance);

-- Composite Indexes
CREATE INDEX idx_flights_source_target ON flights(source, target);
CREATE INDEX idx_flights_departure_date ON flights(DATE(departure_ts));

-- Verification

-- Count
SELECT 'Airlines' AS table_name, COUNT(*) AS count FROM airlines
UNION ALL
SELECT 'Airports', COUNT(*) FROM airports
UNION ALL
SELECT 'Flights', COUNT(*) FROM flights
ORDER BY table_name;

-- Data samples
SELECT * FROM airlines LIMIT 5;
SELECT * FROM airports LIMIT 5;
SELECT * FROM flights LIMIT 5;
