# Part 1: Data Import and Modeling

## Overview
Import GTFS data into PostgreSQL (relational) and Neo4j (graph) databases with proper constraints, indexes, and numeric edge properties.

## Requirements from CONSIGNES.MD

### Must Implement
- ✅ PostgreSQL relational schema
- ✅ Neo4j graph model
- ✅ Numeric properties on edges (travel_time, transfer_time, etc.)
- ✅ Integrity constraints (primary keys, foreign keys, uniqueness)
- ✅ Indexes for performance
- ✅ Document all decisions in report

## Graph Model Options

### Option A: Stop-Centric (Recommended for Path Queries)
Best for shortest path and connectivity queries.

```cypher
(:Stop)-[:CONNECTED_BY {trip_id, departure_time, arrival_time, travel_time}]->(:Stop)
(:Stop)-[:TRANSFER {min_transfer_time}]->(:Stop)
(:Stop)-[:PATHWAY {traversal_time, length}]->(:Stop)
```

**Pros**: Direct stop-to-stop paths, fast shortest path
**Cons**: Loses trip-level information, many duplicate edges

### Option B: Trip-Centric
Best for trip-based queries.

```cypher
(:Stop)<-[:STARTS_AT]-(:Trip)-[:ENDS_AT]->(:Stop)
(:Trip)-[:NEXT_STOP {stop_sequence, arrival_time, departure_time}]->(:Stop)
```

**Pros**: Preserves trip information
**Cons**: More hops for stop-to-stop paths

### Option C: Hybrid (Most Expressive)
Combines both approaches.

```cypher
(:Stop)-[:STOP_TIME {arrival_time, departure_time, stop_sequence}]-(:Trip)
(:Trip)-[:BELONGS_TO]->(:Route)
(:Route)-[:OPERATED_BY]->(:Agency)
(:Stop)-[:TRANSFER {min_transfer_time}]->(:Stop)
(:Stop)-[:PATHWAY {traversal_time, length}]->(:Stop)
```

**Pros**: Maximum flexibility, preserves all relationships
**Cons**: More complex, larger memory footprint

**Recommendation**: Start with Option C (Hybrid), can derive Option A if needed

## PostgreSQL Schema

### Tables (from GTFS)
```sql
-- Already normalized in GTFS format
CREATE TABLE agency (...);
CREATE TABLE routes (...);
CREATE TABLE trips (...);
CREATE TABLE stops (...);
CREATE TABLE stop_times (...);
CREATE TABLE transfers (...);
CREATE TABLE pathways (...);
CREATE TABLE calendar (...);
CREATE TABLE calendar_dates (...);
```

### Constraints
```sql
-- Primary Keys
ALTER TABLE stops ADD PRIMARY KEY (stop_id);
ALTER TABLE routes ADD PRIMARY KEY (route_id);
ALTER TABLE trips ADD PRIMARY KEY (trip_id);
ALTER TABLE stop_times ADD PRIMARY KEY (trip_id, stop_sequence);
ALTER TABLE transfers ADD PRIMARY KEY (from_stop_id, to_stop_id);

-- Foreign Keys
ALTER TABLE trips ADD FOREIGN KEY (route_id) REFERENCES routes(route_id);
ALTER TABLE stop_times ADD FOREIGN KEY (trip_id) REFERENCES trips(trip_id);
ALTER TABLE stop_times ADD FOREIGN KEY (stop_id) REFERENCES stops(stop_id);

-- Check Constraints
ALTER TABLE stops ADD CHECK (wheelchair_boarding IN (0, 1, 2));
ALTER TABLE stops ADD CHECK (stop_lat BETWEEN -90 AND 90);
ALTER TABLE stops ADD CHECK (stop_lon BETWEEN -180 AND 180);
```

### Indexes
```sql
-- Location queries
CREATE INDEX idx_stops_location ON stops(stop_lat, stop_lon);

-- Join optimization
CREATE INDEX idx_stop_times_stop ON stop_times(stop_id);
CREATE INDEX idx_stop_times_trip ON stop_times(trip_id);
CREATE INDEX idx_trips_route ON trips(route_id);

-- Transfer queries
CREATE INDEX idx_transfers_from ON transfers(from_stop_id);
CREATE INDEX idx_transfers_to ON transfers(to_stop_id);
```

## Neo4j Constraints and Indexes

### Constraints
```cypher
// Uniqueness (also creates indexes)
CREATE CONSTRAINT stop_id_unique FOR (s:Stop) REQUIRE s.stop_id IS UNIQUE;
CREATE CONSTRAINT route_id_unique FOR (r:Route) REQUIRE r.route_id IS UNIQUE;
CREATE CONSTRAINT trip_id_unique FOR (t:Trip) REQUIRE t.trip_id IS UNIQUE;
CREATE CONSTRAINT agency_id_unique FOR (a:Agency) REQUIRE a.agency_id IS UNIQUE;

// Existence
CREATE CONSTRAINT stop_name_exists FOR (s:Stop) REQUIRE s.stop_name IS NOT NULL;
```

### Indexes
```cypher
// Location queries
CREATE INDEX stop_location FOR (s:Stop) ON (s.stop_lat, s.stop_lon);

// Route queries
CREATE INDEX trip_route FOR (t:Trip) ON (t.route_id);
CREATE INDEX route_type FOR (r:Route) ON (r.route_type);
```

## Import Strategy

### ⚠️ IMPORTANT : Subsetting et Cohérence des Données

**Problème 1 - Volumétrie** : Les fichiers GTFS originaux sont trop volumineux :
- `stop_times.csv` : 796 MB (~15M lignes)
- `trips.csv` : 33.7 MB (~500K lignes)

L'import direct provoque des erreurs de mémoire (Neo4j) ou des temps de traitement prohibitifs (plusieurs heures).

**Problème 2 - Cohérence** : Si on filtre uniquement `stop_times.csv`, on obtient :
- Des `trip_id` référencés qui n'existent pas dans `trips.csv` (violation de clé étrangère)
- Impossible de créer les relations `BELONGS_TO` vers les Routes
- Données incohérentes pour les deux bases de données

**Solution** : Utiliser des fichiers subset générés par `create_subset_by_route.sh`

Le script **filtre de manière cohérente** :

```bash
# Génération des subsets (lignes 3, 7, 14, 11 par défaut)
bash create_subset_by_route.sh

# Personnalisation (exemple : ligne 11 uniquement)
METRO_LINES="11" bash create_subset_by_route.sh

# Plusieurs lignes
METRO_LINES="1 4 6 14" bash create_subset_by_route.sh
```

**Résultat** :
- `export/trips_subset.csv` : Uniquement les trajets des lignes de métro sélectionnées
- `export/stop_times_subset.csv` : Uniquement les horaires correspondants

**Réduction typique** : ~95% de données en moins (de 796 MB à ~40 MB pour 4 lignes de métro)

**Choix des lignes** :
- Lignes 3, 7, 14, 11 (par défaut) : Réseau représentatif pour les requêtes de chemin
- Ligne 11 seule : Datasets minimal pour tests rapides
- Lignes 1, 4, 6, 14 : Réseau central de Paris

### PostgreSQL: COPY Command
```sql
\COPY agency FROM './export/agency.csv' CSV HEADER;
\COPY calendar FROM './export/calendar.csv' CSV HEADER;
\COPY calendar_dates FROM './export/calendar_dates.csv' CSV HEADER;
\COPY routes FROM './export/routes.csv' CSV HEADER;
\COPY stops FROM './export/stops.csv' CSV HEADER;
\COPY trips FROM './export/trips.csv' CSV HEADER;
\COPY transfers FROM './export/transfers.csv' CSV HEADER;
\COPY pathways FROM './export/pathways.csv' CSV HEADER;
\COPY stop_times FROM './export/stop_times.csv' CSV HEADER;  -- WARNING: 796 MB!
```

### Neo4j: LOAD CSV with Batching

**Step 1: Load Nodes (Create constraints first!)**
```cypher
// Agencies
LOAD CSV WITH HEADERS FROM 'file:///agency.csv' AS row
CREATE (:Agency {
  agency_id: row.agency_id,
  agency_name: row.agency_name,
  agency_url: row.agency_url,
  agency_timezone: row.agency_timezone
});

// Routes
LOAD CSV WITH HEADERS FROM 'file:///routes.csv' AS row
CREATE (:Route {
  route_id: row.route_id,
  agency_id: row.agency_id,
  route_short_name: row.route_short_name,
  route_long_name: row.route_long_name,
  route_type: toInteger(row.route_type),
  route_color: row.route_color
});

// Stops
LOAD CSV WITH HEADERS FROM 'file:///stops.csv' AS row
CREATE (:Stop {
  stop_id: row.stop_id,
  stop_name: row.stop_name,
  stop_lat: toFloat(row.stop_lat),
  stop_lon: toFloat(row.stop_lon),
  wheelchair_boarding: toInteger(row.wheelchair_boarding),
  location_type: toInteger(row.location_type),
  parent_station: row.parent_station
});

// Trips - UTILISER LE SUBSET!
// Note: trips_subset.csv est généré par create_subset_by_route.sh
LOAD CSV WITH HEADERS FROM 'file:///trips_subset.csv' AS row
CREATE (:Trip {
  trip_id: row.trip_id,
  route_id: row.route_id,
  service_id: row.service_id,
  trip_headsign: row.trip_headsign,
  direction_id: toInteger(row.direction_id),
  wheelchair_accessible: toInteger(row.wheelchair_accessible)
});
```

**Step 2: Create Relationships (WITH BATCHING!)**
```cypher
// Route -> Agency
CALL {
  LOAD CSV WITH HEADERS FROM 'file:///routes.csv' AS row
  MATCH (r:Route {route_id: row.route_id})
  MATCH (a:Agency {agency_id: row.agency_id})
  CREATE (r)-[:OPERATED_BY]->(a)
} IN TRANSACTIONS OF 10000 ROWS;

// Trip -> Route
CALL {
  LOAD CSV WITH HEADERS FROM 'file:///trips_subset.csv' AS row
  MATCH (t:Trip {trip_id: row.trip_id})
  MATCH (r:Route {route_id: row.route_id})
  CREATE (t)-[:BELONGS_TO]->(r)
} IN TRANSACTIONS OF 10000 ROWS;

// Stop -> Trip (from stop_times) - UTILISER LE SUBSET!
CALL {
  LOAD CSV WITH HEADERS FROM 'file:///stop_times_subset.csv' AS row
  MATCH (s:Stop {stop_id: row.stop_id})
  MATCH (t:Trip {trip_id: row.trip_id})
  CREATE (s)-[:STOP_TIME {
    arrival_time: row.arrival_time,
    departure_time: row.departure_time,
    stop_sequence: toInteger(row.stop_sequence)
  }]->(t)
} IN TRANSACTIONS OF 5000 ROWS;

// Transfers
CALL {
  LOAD CSV WITH HEADERS FROM 'file:///transfers.csv' AS row
  MATCH (from:Stop {stop_id: row.from_stop_id})
  MATCH (to:Stop {stop_id: row.to_stop_id})
  CREATE (from)-[:TRANSFER {
    transfer_type: toInteger(row.transfer_type),
    min_transfer_time: toInteger(row.min_transfer_time)
  }]->(to)
} IN TRANSACTIONS OF 10000 ROWS;

// Pathways
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
} IN TRANSACTIONS OF 10000 ROWS;
```

## Common Pitfalls

### 1. Time Format Issues
GTFS times can exceed 24:00:00 (e.g., 25:30:00 for 1:30 AM next day)
- **PostgreSQL**: Use INTERVAL or TEXT, not TIME type
- **Neo4j**: Store as string or convert to minutes since midnight (integer)

### 2. Large File Performance
stop_times.csv is 796 MB!
- **Create constraints BEFORE loading** (enables index lookups)
- **Use batching** for Neo4j (5000-10000 rows)
- **Consider subsetting** for initial testing

### 3. Data Subsetting for Testing
```sql
-- PostgreSQL: Extract one route
CREATE TABLE stops_subset AS
SELECT DISTINCT s.* FROM stops s
JOIN stop_times st ON s.stop_id = st.stop_id
JOIN trips t ON st.trip_id = t.trip_id
WHERE t.route_id = '100110';  -- Example: RER A
```

### 4. Calculating Derived Properties
You need travel_time between consecutive stops:

```sql
-- PostgreSQL window function
WITH ordered_stops AS (
  SELECT
    trip_id, stop_id, stop_sequence,
    departure_time, arrival_time,
    LEAD(stop_id) OVER (PARTITION BY trip_id ORDER BY stop_sequence) as next_stop_id,
    LEAD(arrival_time) OVER (PARTITION BY trip_id ORDER BY stop_sequence) as next_arrival_time
  FROM stop_times
)
SELECT
  trip_id, stop_id, next_stop_id,
  next_arrival_time - departure_time as travel_time
FROM ordered_stops
WHERE next_stop_id IS NOT NULL;
```

## Validation Queries

### PostgreSQL
```sql
-- Count records
SELECT 'stops' as table_name, COUNT(*) FROM stops
UNION ALL SELECT 'routes', COUNT(*) FROM routes
UNION ALL SELECT 'trips', COUNT(*) FROM trips
UNION ALL SELECT 'stop_times', COUNT(*) FROM stop_times;

-- Check for orphans
SELECT COUNT(*) FROM trips t
LEFT JOIN routes r ON t.route_id = r.route_id
WHERE r.route_id IS NULL;
```

### Neo4j
```cypher
// Count nodes
MATCH (n) RETURN labels(n)[0] as label, count(*) as count
ORDER BY count DESC;

// Count relationships
MATCH ()-[r]->() RETURN type(r) as rel_type, count(*) as count
ORDER BY count DESC;

// Check connectivity
MATCH (s:Stop) WHERE NOT (s)--() RETURN count(s) as isolated_stops;
```

## Import Checklist

- [ ] 1. Create PostgreSQL database and tables
- [ ] 2. Create Neo4j database
- [ ] 3. Define constraints in both databases
- [ ] 4. Test import on small subset (one route)
- [ ] 5. Verify subset data integrity
- [ ] 6. Import full PostgreSQL data using COPY
- [ ] 7. Import Neo4j nodes (agencies, routes, stops, trips)
- [ ] 8. Import Neo4j relationships (with batching!)
- [ ] 9. Create indexes in both databases
- [ ] 10. Run validation queries
- [ ] 11. Calculate derived properties (travel_time)
- [ ] 12. Document all decisions for report

## Next Steps
Once data is loaded, proceed to Part 2: Query Development (see `docs/PART2.MD`)
