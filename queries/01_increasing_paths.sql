-- Pattern 1: Increasing Property Paths (Departure Times) - SQL VERSION
-- Objectif: Trouver des chemins où les horaires de départ augmentent strictement
-- Utilisation de WITH RECURSIVE (CTE récursive)

-- ============================================================================
-- SQL RECURSIVE CTE - Version avec contrainte croissante
-- ============================================================================
-- Cette version filtre directement lors de la récursion

WITH RECURSIVE increasing_path AS (
  -- Cas de base: premier arrêt d'un trajet
  SELECT
    st.trip_id,
    st.stop_id,
    st.stop_sequence,
    st.departure_time,
    ARRAY[st.stop_id] as path_stops,
    ARRAY[st.departure_time::text] as path_times,
    1 as path_length
  FROM stop_times st
  WHERE st.stop_sequence = 1

  UNION ALL

  -- Cas récursif: ajouter l'arrêt suivant si l'heure augmente
  SELECT
    st.trip_id,
    st.stop_id,
    st.stop_sequence,
    st.departure_time,
    ip.path_stops || st.stop_id,
    ip.path_times || st.departure_time::text,
    ip.path_length + 1
  FROM increasing_path ip
  JOIN stop_times st
    ON ip.trip_id = st.trip_id
    AND st.stop_sequence = ip.stop_sequence + 1
  WHERE st.departure_time > ip.departure_time  -- Contrainte croissante
    AND ip.path_length < 5  -- Limite pour éviter explosion
)
-- Sélectionner uniquement les chemins d'au moins 2 stops
SELECT
  ip.trip_id,
  ip.path_length,
  array_agg(s.stop_name ORDER BY array_position(ip.path_stops, s.stop_id)) as stop_names,
  ip.path_times
FROM increasing_path ip
JOIN stops s ON s.stop_id = ANY(ip.path_stops)
WHERE ip.path_length >= 2
GROUP BY ip.trip_id, ip.path_length, ip.path_times, ip.path_stops
ORDER BY ip.path_length DESC
LIMIT 10;

-- ============================================================================
-- Version simplifiée pour une ligne spécifique
-- ============================================================================
-- Filtrage sur la ligne de métro 3

WITH RECURSIVE increasing_path AS (
  SELECT
    st.trip_id,
    st.stop_id,
    st.stop_sequence,
    st.departure_time,
    ARRAY[st.stop_id] as path_stops,
    1 as path_length
  FROM stop_times st
  JOIN trips t ON st.trip_id = t.trip_id
  JOIN routes r ON t.route_id = r.route_id
  WHERE st.stop_sequence = 1
    AND r.route_long_name = '3'

  UNION ALL

  SELECT
    st.trip_id,
    st.stop_id,
    st.stop_sequence,
    st.departure_time,
    ip.path_stops || st.stop_id,
    ip.path_length + 1
  FROM increasing_path ip
  JOIN stop_times st
    ON ip.trip_id = st.trip_id
    AND st.stop_sequence = ip.stop_sequence + 1
  WHERE st.departure_time > ip.departure_time
    AND ip.path_length < 5
)
SELECT
  ip.trip_id,
  ip.path_length,
  array_length(ip.path_stops, 1) as stop_count
FROM increasing_path ip
WHERE ip.path_length >= 2
ORDER BY ip.path_length DESC
LIMIT 10;

-- ============================================================================
-- Version avec temps d'exécution mesuré
-- ============================================================================
-- Utilise \timing dans psql pour mesurer la performance

\timing on

WITH RECURSIVE increasing_path AS (
  SELECT
    st.trip_id,
    st.stop_sequence,
    st.departure_time,
    1 as path_length
  FROM stop_times st
  JOIN trips t ON st.trip_id = t.trip_id
  JOIN routes r ON t.route_id = r.route_id
  WHERE st.stop_sequence = 1
    AND r.route_long_name = '3'

  UNION ALL

  SELECT
    st.trip_id,
    st.stop_sequence,
    st.departure_time,
    ip.path_length + 1
  FROM increasing_path ip
  JOIN stop_times st
    ON ip.trip_id = st.trip_id
    AND st.stop_sequence = ip.stop_sequence + 1
  WHERE st.departure_time > ip.departure_time
    AND ip.path_length < 10  -- Tester avec différentes limites
)
SELECT count(*) as path_count, max(path_length) as max_length
FROM increasing_path;

\timing off

-- ============================================================================
-- Test de performance: mesurer le timeout threshold
-- ============================================================================
-- Augmenter progressivement la limite pour voir où ça timeout

-- Test avec limite 3
\echo 'Test avec limite 3'
WITH RECURSIVE increasing_path AS (
  SELECT st.trip_id, st.stop_sequence, st.departure_time, 1 as length
  FROM stop_times st
  JOIN trips t ON st.trip_id = t.trip_id
  JOIN routes r ON t.route_id = r.route_id
  WHERE st.stop_sequence = 1 AND r.route_long_name = '3'

  UNION ALL

  SELECT st.trip_id, st.stop_sequence, st.departure_time, ip.length + 1
  FROM increasing_path ip
  JOIN stop_times st ON ip.trip_id = st.trip_id
    AND st.stop_sequence = ip.stop_sequence + 1
  WHERE st.departure_time > ip.departure_time AND ip.length < 3
)
SELECT count(*) FROM increasing_path;

-- Test avec limite 5
\echo 'Test avec limite 5'
WITH RECURSIVE increasing_path AS (
  SELECT st.trip_id, st.stop_sequence, st.departure_time, 1 as length
  FROM stop_times st
  JOIN trips t ON st.trip_id = t.trip_id
  JOIN routes r ON t.route_id = r.route_id
  WHERE st.stop_sequence = 1 AND r.route_long_name = '3'

  UNION ALL

  SELECT st.trip_id, st.stop_sequence, st.departure_time, ip.length + 1
  FROM increasing_path ip
  JOIN stop_times st ON ip.trip_id = st.trip_id
    AND st.stop_sequence = ip.stop_sequence + 1
  WHERE st.departure_time > ip.departure_time AND ip.length < 5
)
SELECT count(*) FROM increasing_path;

-- Test avec limite 10
\echo 'Test avec limite 10'
WITH RECURSIVE increasing_path AS (
  SELECT st.trip_id, st.stop_sequence, st.departure_time, 1 as length
  FROM stop_times st
  JOIN trips t ON st.trip_id = t.trip_id
  JOIN routes r ON t.route_id = r.route_id
  WHERE st.stop_sequence = 1 AND r.route_long_name = '3'

  UNION ALL

  SELECT st.trip_id, st.stop_sequence, st.departure_time, ip.length + 1
  FROM increasing_path ip
  JOIN stop_times st ON ip.trip_id = st.trip_id
    AND st.stop_sequence = ip.stop_sequence + 1
  WHERE st.departure_time > ip.departure_time AND ip.length < 10
)
SELECT count(*) FROM increasing_path;

-- ============================================================================
-- EXPLAIN ANALYZE pour obtenir le plan d'exécution
-- ============================================================================

EXPLAIN ANALYZE
WITH RECURSIVE increasing_path AS (
  SELECT
    st.trip_id,
    st.stop_sequence,
    st.departure_time,
    1 as path_length
  FROM stop_times st
  JOIN trips t ON st.trip_id = t.trip_id
  JOIN routes r ON t.route_id = r.route_id
  WHERE st.stop_sequence = 1
    AND r.route_long_name = '3'

  UNION ALL

  SELECT
    st.trip_id,
    st.stop_sequence,
    st.departure_time,
    ip.path_length + 1
  FROM increasing_path ip
  JOIN stop_times st
    ON ip.trip_id = st.trip_id
    AND st.stop_sequence = ip.stop_sequence + 1
  WHERE st.departure_time > ip.departure_time
    AND ip.path_length < 5
)
SELECT count(*) FROM increasing_path;

-- Questions pour le rapport:
-- 1. Performance SQL vs Cypher 5 sur ce pattern?
-- 2. À partir de quelle limite la requête SQL devient lente?
-- 3. Quel est le plan d'exécution (hash join, nested loop, etc.)?
-- 4. Combien de lignes sont scannées?
