-- Pattern 2: Quantified Graph Patterns - SQL VERSION
-- Objectif: Requêtes équivalentes avec agrégations et filtres SQL

-- ============================================================================
-- Arrêts avec au moins 3 lignes accessibles PMR
-- ============================================================================

SELECT
  s.stop_name,
  s.stop_id,
  COUNT(DISTINCT r.route_id) as accessible_routes
FROM stops s
JOIN stop_times st ON s.stop_id = st.stop_id
JOIN trips t ON st.trip_id = t.trip_id
JOIN routes r ON t.route_id = r.route_id
WHERE t.wheelchair_accessible = 1
GROUP BY s.stop_name, s.stop_id
HAVING COUNT(DISTINCT r.route_id) >= 3
ORDER BY accessible_routes DESC
LIMIT 20;

-- ============================================================================
-- Arrêts avec au moins 2 correspondances rapides (<2 min)
-- ============================================================================

SELECT
  s.stop_name as hub,
  s.stop_id,
  COUNT(tf.to_stop_id) as fast_transfers
FROM stops s
JOIN transfers tf ON s.stop_id = tf.from_stop_id
WHERE tf.min_transfer_time < 120
  AND tf.min_transfer_time IS NOT NULL
GROUP BY s.stop_name, s.stop_id
HAVING COUNT(tf.to_stop_id) >= 2
ORDER BY fast_transfers DESC
LIMIT 20;

-- ============================================================================
-- CAS COMPLEXE: Hubs de correspondance (multi-critères)
-- ============================================================================
-- Arrêts qui sont à la fois:
-- - Desservis par plusieurs lignes de métro
-- - Avec des correspondances rapides
-- - Et accessibles PMR

WITH metro_stops AS (
  SELECT
    s.stop_id,
    s.stop_name,
    COUNT(DISTINCT r.route_id) as metro_lines
  FROM stops s
  JOIN stop_times st ON s.stop_id = st.stop_id
  JOIN trips t ON st.trip_id = t.trip_id
  JOIN routes r ON t.route_id = r.route_id
  WHERE r.route_type = 1
  GROUP BY s.stop_id, s.stop_name
  HAVING COUNT(DISTINCT r.route_id) >= 2
),
transfer_stops AS (
  SELECT
    s.stop_id,
    COUNT(tf.to_stop_id) as transfer_count
  FROM stops s
  JOIN transfers tf ON s.stop_id = tf.from_stop_id
  WHERE tf.min_transfer_time < 180
    AND tf.min_transfer_time IS NOT NULL
  GROUP BY s.stop_id
),
accessible_stops AS (
  SELECT
    s.stop_id,
    COUNT(DISTINCT t.trip_id) as accessible_trips
  FROM stops s
  JOIN stop_times st ON s.stop_id = st.stop_id
  JOIN trips t ON st.trip_id = t.trip_id
  WHERE t.wheelchair_accessible = 1
  GROUP BY s.stop_id
)
SELECT
  ms.stop_name as hub,
  ms.metro_lines,
  COALESCE(ts.transfer_count, 0) as fast_transfers,
  COALESCE(acs.accessible_trips, 0) as accessible_trips
FROM metro_stops ms
LEFT JOIN transfer_stops ts ON ms.stop_id = ts.stop_id
LEFT JOIN accessible_stops acs ON ms.stop_id = acs.stop_id
WHERE COALESCE(acs.accessible_trips, 0) > 0
ORDER BY ms.metro_lines DESC, fast_transfers DESC
LIMIT 10;

-- ============================================================================
-- VERSION SIMPLIFIÉE: Comptage de routes par arrêt
-- ============================================================================

SELECT
  s.stop_name,
  COUNT(DISTINCT r.route_id) as route_count
FROM stops s
JOIN stop_times st ON s.stop_id = st.stop_id
JOIN trips t ON st.trip_id = t.trip_id
JOIN routes r ON t.route_id = r.route_id
GROUP BY s.stop_name, s.stop_id
HAVING COUNT(DISTINCT r.route_id) >= 3
ORDER BY route_count DESC
LIMIT 10;

-- ============================================================================
-- PATTERN AVANCÉ: Hubs multi-modaux
-- ============================================================================
-- Arrêts connectant plusieurs types de transport

SELECT
  s.stop_name as multimodal_hub,
  COUNT(DISTINCT CASE WHEN r.route_type = 1 THEN r.route_id END) as metros,
  COUNT(DISTINCT CASE WHEN r.route_type = 3 THEN r.route_id END) as buses,
  COUNT(DISTINCT CASE WHEN r.route_type = 2 THEN r.route_id END) as trains,
  (CASE WHEN COUNT(DISTINCT CASE WHEN r.route_type = 1 THEN r.route_id END) > 0 THEN 1 ELSE 0 END +
   CASE WHEN COUNT(DISTINCT CASE WHEN r.route_type = 3 THEN r.route_id END) > 0 THEN 1 ELSE 0 END +
   CASE WHEN COUNT(DISTINCT CASE WHEN r.route_type = 2 THEN r.route_id END) > 0 THEN 1 ELSE 0 END) as transport_types
FROM stops s
JOIN stop_times st ON s.stop_id = st.stop_id
JOIN trips t ON st.trip_id = t.trip_id
JOIN routes r ON t.route_id = r.route_id
GROUP BY s.stop_name, s.stop_id
HAVING (CASE WHEN COUNT(DISTINCT CASE WHEN r.route_type = 1 THEN r.route_id END) > 0 THEN 1 ELSE 0 END +
        CASE WHEN COUNT(DISTINCT CASE WHEN r.route_type = 3 THEN r.route_id END) > 0 THEN 1 ELSE 0 END +
        CASE WHEN COUNT(DISTINCT CASE WHEN r.route_type = 2 THEN r.route_id END) > 0 THEN 1 ELSE 0 END) >= 2
ORDER BY metros DESC, buses DESC, trains DESC
LIMIT 15;

-- ============================================================================
-- COMPARAISON DE STRATÉGIES: Subqueries vs Joins
-- ============================================================================

-- Version avec subqueries (peut être plus lent)
SELECT
  s.stop_name,
  (SELECT COUNT(DISTINCT r.route_id)
   FROM stop_times st
   JOIN trips t ON st.trip_id = t.trip_id
   JOIN routes r ON t.route_id = r.route_id
   WHERE st.stop_id = s.stop_id AND t.wheelchair_accessible = 1) as accessible_routes
FROM stops s
WHERE (SELECT COUNT(DISTINCT r.route_id)
       FROM stop_times st
       JOIN trips t ON st.trip_id = t.trip_id
       JOIN routes r ON t.route_id = r.route_id
       WHERE st.stop_id = s.stop_id AND t.wheelchair_accessible = 1) >= 3
ORDER BY accessible_routes DESC
LIMIT 10;

-- ============================================================================
-- EXPLAIN ANALYZE
-- ============================================================================

EXPLAIN ANALYZE
SELECT
  s.stop_name,
  s.stop_id,
  COUNT(DISTINCT r.route_id) as accessible_routes
FROM stops s
JOIN stop_times st ON s.stop_id = st.stop_id
JOIN trips t ON st.trip_id = t.trip_id
JOIN routes r ON t.route_id = r.route_id
WHERE t.wheelchair_accessible = 1
GROUP BY s.stop_name, s.stop_id
HAVING COUNT(DISTINCT r.route_id) >= 3
ORDER BY accessible_routes DESC
LIMIT 10;

-- Questions pour le rapport:
-- 1. Performance des CTEs vs subqueries vs joins?
-- 2. Index utilisés pour les GROUP BY?
-- 3. Hash aggregate vs Group aggregate?
-- 4. SQL plus rapide que Cypher sur ce type de requête?
