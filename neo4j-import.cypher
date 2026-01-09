// Neo4j IDFM Import Script

// CONTRAINTES
CREATE CONSTRAINT agency_id_unique IF NOT EXISTS
FOR (a:Agency) REQUIRE a.agency_id IS UNIQUE;

CREATE CONSTRAINT route_id_unique IF NOT EXISTS
FOR (r:Route) REQUIRE r.route_id IS UNIQUE;

CREATE CONSTRAINT stop_id_unique IF NOT EXISTS
FOR (s:Stop) REQUIRE s.stop_id IS UNIQUE;

CREATE CONSTRAINT trip_id_unique IF NOT EXISTS
FOR (t:Trip) REQUIRE t.trip_id IS UNIQUE;

// agency
LOAD CSV WITH HEADERS FROM 'file:///agency.csv' AS row
CREATE (:Agency {
  agency_id: row.agency_id,
  agency_name: row.agency_name,
  agency_url: row.agency_url,
  agency_timezone: row.agency_timezone
});

MATCH (a:Agency) RETURN a.agency_name;

// routes
CALL {
  LOAD CSV WITH HEADERS FROM 'file:///routes.csv' AS row
  CREATE (:Route {
    route_id: row.route_id,
    agency_id: row.agency_id,
    route_short_name: row.route_short_name,
    route_long_name: row.route_long_name,
    route_type: toInteger(row.route_type),
    route_color: row.route_color
  })
} IN TRANSACTIONS OF 1000 ROWS;

MATCH (r:Route) RETURN count(r);

// stops
CALL {
  LOAD CSV WITH HEADERS FROM 'file:///stops.csv' AS row
  CREATE (:Stop {
    stop_id: row.stop_id,
    stop_name: row.stop_name,
    stop_lat: toFloat(row.stop_lat),
    stop_lon: toFloat(row.stop_lon),
    location_type: toInteger(row.location_type),
    wheelchair_boarding: toInteger(row.wheelchair_boarding),
    parent_station: row.parent_station
  })
} IN TRANSACTIONS OF 5000 ROWS;

MATCH (s:Stop) RETURN count(s);

// trips
CALL {
  LOAD CSV WITH HEADERS FROM 'file:///trips.csv' AS row
  CREATE (:Trip {
    trip_id: row.trip_id,
    route_id: row.route_id,
    service_id: row.service_id,
    trip_headsign: row.trip_headsign,
    direction_id: toInteger(row.direction_id),
    wheelchair_accessible: toInteger(row.wheelchair_accessible)
  })
} IN TRANSACTIONS OF 10000 ROWS;

MATCH (t:Trip) RETURN count(t);

// lier routes <-> agencies
CALL {
  LOAD CSV WITH HEADERS FROM 'file:///routes.csv' AS row
  MATCH (r:Route {route_id: row.route_id})
  MATCH (a:Agency {agency_id: row.agency_id})
  CREATE (r)-[:OPERATED_BY]->(a)
} IN TRANSACTIONS OF 5000 ROWS;

MATCH ()-[r:OPERATED_BY]->() RETURN count(r);

// lier trips <-> routes
CALL {
  LOAD CSV WITH HEADERS FROM 'file:///trips.csv' AS row
  MATCH (t:Trip {trip_id: row.trip_id})
  MATCH (r:Route {route_id: row.route_id})
  CREATE (t)-[:BELONGS_TO]->(r)
} IN TRANSACTIONS OF 10000 ROWS;

MATCH ()-[r:BELONGS_TO]->() RETURN count(r);

// transfers
CALL {
  LOAD CSV WITH HEADERS FROM 'file:///transfers.csv' AS row
  MATCH (from:Stop {stop_id: row.from_stop_id})
  MATCH (to:Stop {stop_id: row.to_stop_id})
  CREATE (from)-[:TRANSFER {
    transfer_type: toInteger(row.transfer_type),
    min_transfer_time: toInteger(row.min_transfer_time)
  }]->(to)
} IN TRANSACTIONS OF 10000 ROWS;

MATCH ()-[r:TRANSFER]->() RETURN count(r);

// pathways
CALL {
  LOAD CSV WITH HEADERS FROM 'file:///pathways.csv' AS row
  MATCH (from:Stop {stop_id: row.from_stop_id})
  MATCH (to:Stop {stop_id: row.to_stop_id})
  CREATE (from)-[:PATHWAY {
    pathway_mode: toInteger(row.pathway_mode),
    is_bidirectional: toInteger(row.is_bidirectional),
    length: toFloat(row.length),
    traversal_time: toInteger(row.traversal_time)
  }]->(to)
} IN TRANSACTIONS OF 5000 ROWS;

MATCH ()-[r:PATHWAY]->() RETURN count(r);

// stop_times (on prend mini subset - 100k lignes au lieu de 9M)
CALL {
  LOAD CSV WITH HEADERS FROM 'file:///stop_times_mini.csv' AS row
  MATCH (s:Stop {stop_id: row.stop_id})
  MATCH (t:Trip {trip_id: row.trip_id})
  CREATE (s)-[:STOP_TIME {
    arrival_time: row.arrival_time,
    departure_time: row.departure_time,
    stop_sequence: toInteger(row.stop_sequence)
  }]->(t)
} IN TRANSACTIONS OF 5000 ROWS;

MATCH ()-[r:STOP_TIME]->() RETURN count(r);

