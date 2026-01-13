// Import Neo4j Cypher

// Import Airlines
LOAD CSV WITH HEADERS FROM 'file:///airlines.csv' AS row
CREATE (:Airline {
  iata_code: row.IATA_CODE,
  name: row.AIRLINE
});

// Import Airports
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

// Contraintes d'unicité
CREATE CONSTRAINT airport_iata_unique IF NOT EXISTS
FOR (a:Airport) REQUIRE a.iata_code IS UNIQUE;

CREATE CONSTRAINT airline_iata_unique IF NOT EXISTS
FOR (al:Airline) REQUIRE al.iata_code IS UNIQUE;

// Index de recherche
CREATE INDEX airport_city IF NOT EXISTS
FOR (a:Airport) ON (a.city);

CREATE INDEX airport_state IF NOT EXISTS
FOR (a:Airport) ON (a.state);

// Import Flights (par batch de 1000)
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

// Index sur les relations FLIGHT
CREATE INDEX flight_departure_time IF NOT EXISTS
FOR ()-[f:FLIGHT]-() ON (f.departure_ts);

CREATE INDEX flight_arrival_time IF NOT EXISTS
FOR ()-[f:FLIGHT]-() ON (f.arrival_ts);

CREATE INDEX flight_delay IF NOT EXISTS
FOR ()-[f:FLIGHT]-() ON (f.delay);

CREATE INDEX flight_distance IF NOT EXISTS
FOR ()-[f:FLIGHT]-() ON (f.distance);

// Comptage noeuds
MATCH (a:Airport) RETURN 'Airports' as type, count(a) as count
UNION
MATCH (al:Airline) RETURN 'Airlines' as type, count(al) as count;

// Comptage relations
MATCH ()-[f:FLIGHT]->() RETURN 'Flights' as type, count(f) as count;

// Top 10 pour tester
MATCH (a:Airport)-[f:FLIGHT]->()
RETURN a.iata_code, a.city, count(f) as outgoing_flights
ORDER BY outgoing_flights DESC
LIMIT 10;
