# Test Queries - Validation des Données

Queries de test pour vérifier la cohérence entre Neo4j et PostgreSQL.

## Neo4j - Queries de Test

```cypher
// 1. Lignes de métro avec le plus d'arrêts
MATCH (s:Stop)-[:STOP_TIME]->(:Trip)-[:BELONGS_TO]->(r:Route {route_type: 1})
RETURN r.route_long_name as ligne, count(DISTINCT s) as nb_arrets
ORDER BY nb_arrets DESC
LIMIT 5;

// Résultat: Ligne 4 (58), Lignes 1,2,3 (50)

// 2. Temps de transfert moyen par station
MATCH (s:Stop)-[t:TRANSFER]->(:Stop)
WHERE t.min_transfer_time IS NOT NULL
RETURN s.stop_name as station,
       count(t) as nb_transferts,
       avg(t.min_transfer_time) as temps_moyen_sec
ORDER BY nb_transferts DESC
LIMIT 10;

// 3. Stations avec le plus de correspondances
MATCH (s:Stop)-[:TRANSFER]->(other:Stop)
RETURN s.stop_name as station, count(DISTINCT other) as nb_correspondances
ORDER BY nb_correspondances DESC
LIMIT 10;

// 4. Chemins entre deux stations via transfers (max 2 sauts)
MATCH path = (s1:Stop {stop_name: 'Châtelet'})-[:TRANSFER*1..2]->(s2:Stop)
WHERE s1 <> s2
RETURN s2.stop_name as destination, length(path) as nb_transferts
LIMIT 10;

// 5. Stations accessibles PMR avec leurs lignes
MATCH (s:Stop {wheelchair_boarding: 1})-[:STOP_TIME]->(:Trip)-[:BELONGS_TO]->(r:Route)
RETURN DISTINCT s.stop_name as station, collect(DISTINCT r.route_long_name)[0..3] as lignes
LIMIT 10;

// Résultat: Vide (pas de wheelchair_boarding=1 dans le subset)

// 6. Validation des relations
MATCH (n) RETURN labels(n)[0] as label, count(*) as count
ORDER BY count DESC;

MATCH ()-[r]->() RETURN type(r) as type, count(*) as count
ORDER BY count DESC;
```

## PostgreSQL - Queries de Test

```sql
-- 1. Lignes de métro avec le plus d'arrêts
SELECT r.route_long_name as ligne, COUNT(DISTINCT s.stop_id) as nb_arrets
FROM stops s
JOIN stop_times st ON s.stop_id = st.stop_id
JOIN trips t ON st.trip_id = t.trip_id
JOIN routes r ON t.route_id = r.route_id
WHERE r.route_type = 1
GROUP BY r.route_long_name
ORDER BY nb_arrets DESC
LIMIT 5;

-- 2. Temps de transfert moyen par station
SELECT s.stop_name as station,
       COUNT(*) as nb_transferts,
       AVG(t.min_transfer_time) as temps_moyen_sec
FROM stops s
JOIN transfers t ON s.stop_id = t.from_stop_id
WHERE t.min_transfer_time IS NOT NULL
GROUP BY s.stop_name
ORDER BY nb_transferts DESC
LIMIT 10;

-- 3. Stations avec le plus de correspondances
SELECT s.stop_name as station, COUNT(DISTINCT t.to_stop_id) as nb_correspondances
FROM stops s
JOIN transfers t ON s.stop_id = t.from_stop_id
GROUP BY s.stop_name
ORDER BY nb_correspondances DESC
LIMIT 10;

-- 4. Query récursive: Stations accessibles depuis Châtelet (max 2 transferts)
WITH RECURSIVE reachable AS (
  SELECT stop_id, stop_name, 0 as distance
  FROM stops
  WHERE stop_name = 'Châtelet'

  UNION

  SELECT s.stop_id, s.stop_name, r.distance + 1
  FROM reachable r
  JOIN transfers t ON r.stop_id = t.from_stop_id
  JOIN stops s ON t.to_stop_id = s.stop_id
  WHERE r.distance < 2
)
SELECT stop_name, MIN(distance) as min_transferts
FROM reachable
WHERE distance > 0
GROUP BY stop_name
ORDER BY min_transferts, stop_name
LIMIT 15;

-- 5. Pathways - Temps de traversée par station
SELECT s.stop_name as station,
       COUNT(*) as nb_chemins,
       AVG(p.traversal_time) as temps_moyen_sec
FROM stops s
JOIN pathways p ON s.stop_id = p.from_stop_id
GROUP BY s.stop_name
ORDER BY nb_chemins DESC
LIMIT 10;

-- 6. Validation des données
SELECT 'agency' as table_name, COUNT(*) as count FROM agency
UNION ALL SELECT 'routes', COUNT(*) FROM routes
UNION ALL SELECT 'stops', COUNT(*) FROM stops
UNION ALL SELECT 'trips', COUNT(*) FROM trips
UNION ALL SELECT 'stop_times', COUNT(*) FROM stop_times
UNION ALL SELECT 'transfers', COUNT(*) FROM transfers
UNION ALL SELECT 'pathways', COUNT(*) FROM pathways
ORDER BY table_name;
```

## Résultats Attendus (Cohérence)

### Comptages
- **Agencies**: 58
- **Routes**: 1983
- **Stops**: 53952
- **Trips**: 15268
- **Stop_times**: ~393k
- **Transfers**: 200444
- **Pathways**: 4911

### Top Stations
- **Mairie**: Hub majeur (2344 transferts, 1623 correspondances)
- **Châtelet**: 734 transferts, temps moyen 260s
- **Hôtel de Ville**: 733 transferts

### Lignes de Métro
- **Ligne 4**: 58 arrêts
- **Lignes 1, 2, 3**: 50 arrêts chacune

## Notes
- ✅ Les résultats sont **identiques** entre Neo4j et PostgreSQL
- ✅ Les subsets sont **cohérents** (mêmes trip_ids)
- ⚠️ Pas de stations PMR dans le subset (wheelchair_boarding=1 absent)
- 🎯 Les deux bases sont prêtes pour Part 2 (comparaisons Cypher 5/25/SQL)
