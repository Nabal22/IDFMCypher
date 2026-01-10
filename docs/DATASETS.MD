# GTFS Dataset Reference

Quick reference for IDFM GTFS data structure. Full details in `README_FICHIERS.md`.

## File Overview

| File | Size | Records (est) | Description |
|------|------|---------------|-------------|
| `stop_times.csv` | 796 MB | ~15M | **LARGEST** - Trip schedules |
| `trips.csv` | 33.7 MB | ~500K | Individual trips |
| `transfers.csv` | 6.2 MB | ~200K | Transfer connections |
| `stops.csv` | 3.5 MB | ~50K | Stop locations |
| `pathways.csv` | 359 KB | ~10K | Pedestrian paths |
| `routes.csv` | 79 KB | ~2K | Transit lines |
| `calendar.csv` | 38 KB | - | Service schedules |
| `calendar_dates.csv` | 32 KB | - | Schedule exceptions |
| `agency.csv` | 7 KB | 2 | RATP, Aérobus |
| `stop_times_subset.csv` | 30 MB | Subset | Metro-only schedules (for Neo4j) |
| `trips_subset.csv` | 6 MB | Subset | Metro-only trips (for Neo4j) | 

### 🚨 Subset Files - Cohérence des Données

Les fichiers `stop_times_subset.csv` et `trips_subset.csv` sont des versions réduites générées pour :
1. **Réduire la volumétrie** : Les fichiers complets (796 MB + 33.7 MB) sont difficiles à traiter
2. **Garantir la cohérence** : Les deux fichiers sont filtrés ensemble pour maintenir l'intégrité référentielle

**Cohérence relationnelle** :
- Tous les `trip_id` référencés dans `stop_times_subset.csv` existent dans `trips_subset.csv`
- Pas de trajets sans horaires, pas d'horaires sans trajet
- Important pour PostgreSQL (clés étrangères) ET Neo4j (relations valides)

**Génération** : Via le script `create_subset_by_route.sh`
```bash
# Par défaut : lignes 3, 7, 14, 11
bash create_subset_by_route.sh

# Personnalisé : ligne 11 uniquement
METRO_LINES="11" bash create_subset_by_route.sh
```

**Stratégie de filtrage** :
1. Sélection des `route_id` correspondant aux lignes de métro (route_type=1)
2. Extraction des `trip_id` associés → `trips_subset.csv`
3. Extraction des `stop_times` correspondants → `stop_times_subset.csv`

## Key Relationships

```
agency (RATP, Aérobus)
  └─> routes (lines: metro, bus, RER)
       └─> trips (individual journeys)
            └─> stop_times (schedule at each stop)
                 └─> stops (stations/stops)

stops
  ├─> transfers (connections between stops)
  └─> pathways (walking paths within stations)
```

## Important Fields

### For Graph Edges (Numeric Properties)
- `min_transfer_time` (transfers.csv) - Transfer duration in seconds
- `traversal_time` (pathways.csv) - Walking time in seconds
- `length` (pathways.csv) - Distance in meters
- `arrival_time`, `departure_time` (stop_times.csv) - Timestamps
- **Derived**: `travel_time` = next arrival - current departure

### For Filtering
- `wheelchair_boarding` (stops.csv): 0=unknown, 1=yes, 2=no
- `wheelchair_accessible` (trips.csv): 0=unknown, 1=yes, 2=no
- `route_type` (routes.csv): 0=tram, 1=metro, 2=train, 3=bus
- `transfer_type` (transfers.csv): 0=recommended, 1=timed, 2=min required, 3=impossible

### For Locations
- `stop_lat`, `stop_lon` (stops.csv) - WGS84 coordinates
- `location_type` (stops.csv): 0=stop, 1=station, 2=entrance

## Common Queries Reference

### PostgreSQL
```sql
-- Stops on a route
SELECT DISTINCT s.stop_name
FROM stops s
JOIN stop_times st ON s.stop_id = st.stop_id
JOIN trips t ON st.trip_id = t.trip_id
WHERE t.route_id = '100110';  -- RER A

-- Travel times between consecutive stops
SELECT st1.stop_id as from_stop, st2.stop_id as to_stop,
       st2.arrival_time - st1.departure_time as travel_time
FROM stop_times st1
JOIN stop_times st2 ON st1.trip_id = st2.trip_id
  AND st2.stop_sequence = st1.stop_sequence + 1;
```

### Neo4j
```cypher
// Stops on a route
MATCH (s:Stop)-[:STOP_TIME]->(:Trip)-[:BELONGS_TO]->(r:Route {route_id: '100110'})
RETURN DISTINCT s.stop_name;

// Transfers from a stop
MATCH (s:Stop {stop_name: 'Châtelet'})-[t:TRANSFER]->(dest:Stop)
RETURN dest.stop_name, t.min_transfer_time
ORDER BY t.min_transfer_time;
```

## Data Quality Notes
- Times can exceed 24:00:00 (e.g., 25:30:00 for 1:30 AM next day)
- Some stops have `parent_station` (entrances → station)
- Not all transfers have `min_transfer_time` (may be NULL)
- `stop_code` is user-facing, `stop_id` is internal

## Subsetting Strategies

### By Route Type
```sql
-- Metro only (route_type = 1)
WHERE route_type = 1

-- Bus only (route_type = 3)
WHERE route_type = 3
```

### By Geographic Area
```sql
-- Paris center (rough bounds)
WHERE stop_lat BETWEEN 48.8 AND 48.9
  AND stop_lon BETWEEN 2.3 AND 2.4
```

### By Time Window
```sql
-- Morning rush hour
WHERE departure_time BETWEEN '07:00:00' AND '09:00:00'
```

## Useful Route IDs
- RER A: `100110`
- Metro Line 1: `100111001` (check actual ID in routes.csv)
- Check `routes.csv` for complete list

## Reference
Full GTFS specification: https://gtfs.org/
IDFM data portal: https://app.idf-mobilites.fr/gtfs
