// ========================================
// Neo4j Database Import Script
// Dataset: US Flight Delays 2015 (Jan 1-7)
// ========================================

// Clean existing data
MATCH (n) DETACH DELETE n;

// ========================================
// 1. Import Airlines
// ========================================
LOAD CSV WITH HEADERS FROM 'file:///airlines.csv' AS row
CREATE (:Airline {
  iata_code: row.IATA_CODE,
  name: row.AIRLINE
});

// ========================================
// 2. Import Airports
// ========================================
LOAD CSV WITH HEADERS FROM 'file:///airports_projet.csv' AS row
CREATE (:Airport {
  iata_code: row.IATA_CODE,
  name: row.AIRPORT,
  city: row.CITY,
  state: row.STATE,
  country: row.COUNTRY,
  latitude: toFloat(row.LATITUDE),
  longitude: toFloat(row.LONGITUDE)
});

// ========================================
// 3. Create Constraints and Indexes
// ========================================

// Constraints (ensure uniqueness)
CREATE CONSTRAINT airport_iata_unique IF NOT EXISTS
FOR (a:Airport) REQUIRE a.iata_code IS UNIQUE;

CREATE CONSTRAINT airline_iata_unique IF NOT EXISTS
FOR (al:Airline) REQUIRE al.iata_code IS UNIQUE;

// Indexes for performance
CREATE INDEX airport_city IF NOT EXISTS
FOR (a:Airport) ON (a.city);

CREATE INDEX airport_state IF NOT EXISTS
FOR (a:Airport) ON (a.state);

// ========================================
// 4. Import Flights (as relationships)
// ========================================

// Load flights in batches for better performance
// Using CALL { ... } IN TRANSACTIONS for large dataset
LOAD CSV WITH HEADERS FROM 'file:///flights_projet.csv' AS row
CALL {
  WITH row
  MATCH (source:Airport {iata_code: row.source})
  MATCH (target:Airport {iata_code: row.target})
  MATCH (airline:Airline {iata_code: row.airline})
  CREATE (source)-[:FLIGHT {
    airline: airline.iata_code,
    airline_name: airline.name,
    departure_ts: datetime(row.departure_ts),
    arrival_ts: datetime(row.arrival_ts),
    distance: toInteger(row.distance),
    delay: toFloat(row.delay)
  }]->(target)
} IN TRANSACTIONS OF 1000 ROWS;

// ========================================
// 5. Create additional indexes on relationships
// ========================================

// Index on flight properties for query performance
CREATE INDEX flight_departure_time IF NOT EXISTS
FOR ()-[f:FLIGHT]-() ON (f.departure_ts);

CREATE INDEX flight_arrival_time IF NOT EXISTS
FOR ()-[f:FLIGHT]-() ON (f.arrival_ts);

CREATE INDEX flight_delay IF NOT EXISTS
FOR ()-[f:FLIGHT]-() ON (f.delay);

CREATE INDEX flight_distance IF NOT EXISTS
FOR ()-[f:FLIGHT]-() ON (f.distance);

// ========================================
// 6. Verification Queries
// ========================================

// Count nodes
MATCH (a:Airport) RETURN 'Airports' as type, count(a) as count
UNION
MATCH (al:Airline) RETURN 'Airlines' as type, count(al) as count;

// Count relationships
MATCH ()-[f:FLIGHT]->() RETURN 'Flights' as type, count(f) as count;

// Sample data
MATCH (source:Airport)-[f:FLIGHT]->(target:Airport)
RETURN source.iata_code, target.iata_code, f.airline, f.departure_ts, f.distance, f.delay
LIMIT 10;

// Hub airports (top 10 by outgoing flights)
MATCH (a:Airport)-[f:FLIGHT]->()
RETURN a.iata_code, a.city, count(f) as outgoing_flights
ORDER BY outgoing_flights DESC
LIMIT 10;
