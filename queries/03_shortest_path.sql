-- Pattern 3: Shortest Path - SQL VERSION
-- Objectif: Plus courts chemins avec CTE récursives
-- Comparaison avec Cypher shortestPath et GDS Dijkstra

-- ============================================================================
-- SETUP: Identifier des arrêts bien connectés
-- ============================================================================

SELECT s.stop_name, s.stop_id, COUNT(*) as transfer_count
FROM stops s
JOIN transfers t ON s.stop_id = t.from_stop_id
GROUP BY s.stop_name, s.stop_id
ORDER BY transfer_count DESC
LIMIT 10;

-- ============================================================================
-- SHORTEST PATH NON PONDÉRÉ (nombre de sauts)
-- ============================================================================
-- BFS avec CTE récursive

WITH RECURSIVE shortest_path AS (
  -- Cas de base: arrêt de départ
  SELECT
    from_stop_id as current_stop,
    to_stop_id as next_stop,
    ARRAY[from_stop_id, to_stop_id] as path,
    1 as depth
  FROM transfers
  WHERE from_stop_id IN (
    SELECT stop_id FROM stops WHERE stop_name LIKE '%Châtelet%' LIMIT 1
  )

  UNION

  -- Cas récursif: explorer les arrêts suivants
  SELECT
    sp.current_stop,
    t.to_stop_id,
    sp.path || t.to_stop_id,
    sp.depth + 1
  FROM shortest_path sp
  JOIN transfers t ON sp.next_stop = t.from_stop_id
  WHERE NOT t.to_stop_id = ANY(sp.path)  -- Éviter les cycles
    AND sp.depth < 10  -- Limite de profondeur
    AND NOT EXISTS (  -- Arrêter si on a déjà atteint la cible
      SELECT 1 FROM shortest_path sp2
      WHERE sp2.next_stop IN (
        SELECT stop_id FROM stops WHERE stop_name LIKE '%Gare%'
      )
    )
)
SELECT
  (SELECT stop_name FROM stops WHERE stop_id = sp.current_stop) as from_stop,
  (SELECT stop_name FROM stops WHERE stop_id = sp.next_stop) as to_stop,
  sp.depth as hops,
  array_length(sp.path, 1) as path_length
FROM shortest_path sp
WHERE sp.next_stop IN (
  SELECT stop_id FROM stops WHERE stop_name LIKE '%Gare%'
)
ORDER BY sp.depth ASC
LIMIT 1;

-- ============================================================================
-- SHORTEST PATH PONDÉRÉ (temps de transfert)
-- ============================================================================
-- Approximation de Dijkstra avec CTE récursive

WITH RECURSIVE weighted_path AS (
  -- Cas de base
  SELECT
    from_stop_id,
    to_stop_id,
    COALESCE(min_transfer_time, 0) as total_cost,
    ARRAY[from_stop_id, to_stop_id] as path,
    1 as depth
  FROM transfers
  WHERE from_stop_id IN (
    SELECT stop_id FROM stops WHERE stop_name LIKE '%Châtelet%' LIMIT 1
  )
    AND min_transfer_time IS NOT NULL

  UNION

  -- Cas récursif
  SELECT
    wp.from_stop_id,
    t.to_stop_id,
    wp.total_cost + COALESCE(t.min_transfer_time, 0),
    wp.path || t.to_stop_id,
    wp.depth + 1
  FROM weighted_path wp
  JOIN transfers t ON wp.to_stop_id = t.from_stop_id
  WHERE NOT t.to_stop_id = ANY(wp.path)
    AND wp.depth < 10
    AND t.min_transfer_time IS NOT NULL
)
SELECT
  (SELECT stop_name FROM stops WHERE stop_id = wp.from_stop_id) as from_stop,
  (SELECT stop_name FROM stops WHERE stop_id = wp.to_stop_id) as to_stop,
  wp.total_cost as total_seconds,
  wp.depth as hops,
  array_length(wp.path, 1) as path_length
FROM weighted_path wp
WHERE wp.to_stop_id IN (
  SELECT stop_id FROM stops WHERE stop_name LIKE '%Gare%'
)
ORDER BY wp.total_cost ASC
LIMIT 1;

-- ============================================================================
-- VERSION OPTIMISÉE: Arrêt précoce
-- ============================================================================
-- Utiliser LIMIT dans la CTE pour arrêter dès qu'on trouve un chemin

WITH RECURSIVE bfs_path AS (
  SELECT
    t.from_stop_id as start_id,
    t.to_stop_id as current_id,
    ARRAY[t.from_stop_id] as path,
    COALESCE(t.min_transfer_time, 0) as cost,
    1 as level
  FROM transfers t
  WHERE t.from_stop_id = (
    SELECT stop_id FROM stops WHERE stop_name LIKE '%Châtelet%' LIMIT 1
  )

  UNION ALL

  SELECT
    bp.start_id,
    t.to_stop_id,
    bp.path || t.to_stop_id,
    bp.cost + COALESCE(t.min_transfer_time, 0),
    bp.level + 1
  FROM bfs_path bp
  JOIN transfers t ON bp.current_id = t.from_stop_id
  WHERE NOT t.to_stop_id = ANY(bp.path)
    AND bp.level < 15
)
SELECT
  s1.stop_name as from_stop,
  s2.stop_name as to_stop,
  bp.level as hops,
  bp.cost as total_seconds,
  array_length(bp.path, 1) as stops_count
FROM bfs_path bp
JOIN stops s1 ON bp.start_id = s1.stop_id
JOIN stops s2 ON bp.current_id = s2.stop_id
WHERE s2.stop_name LIKE '%Gare%'
ORDER BY bp.level ASC, bp.cost ASC
LIMIT 1;

-- ============================================================================
-- ALL SHORTEST PATHS (tous les chemins de longueur minimale)
-- ============================================================================

WITH RECURSIVE all_paths AS (
  SELECT
    from_stop_id,
    to_stop_id,
    ARRAY[from_stop_id, to_stop_id] as path,
    1 as depth
  FROM transfers
  WHERE from_stop_id IN (
    SELECT stop_id FROM stops WHERE stop_name LIKE '%Châtelet%' LIMIT 1
  )

  UNION

  SELECT
    ap.from_stop_id,
    t.to_stop_id,
    ap.path || t.to_stop_id,
    ap.depth + 1
  FROM all_paths ap
  JOIN transfers t ON ap.to_stop_id = t.from_stop_id
  WHERE NOT t.to_stop_id = ANY(ap.path)
    AND ap.depth < 5
),
min_depth AS (
  SELECT MIN(depth) as min_d
  FROM all_paths
  WHERE to_stop_id IN (
    SELECT stop_id FROM stops WHERE stop_name LIKE '%Gare%'
  )
)
SELECT
  (SELECT stop_name FROM stops WHERE stop_id = ap.from_stop_id) as from_stop,
  (SELECT stop_name FROM stops WHERE stop_id = ap.to_stop_id) as to_stop,
  ap.depth,
  COUNT(*) OVER () as total_paths
FROM all_paths ap, min_depth md
WHERE ap.to_stop_id IN (
  SELECT stop_id FROM stops WHERE stop_name LIKE '%Gare%'
)
  AND ap.depth = md.min_d
LIMIT 10;

-- ============================================================================
-- PERFORMANCE TEST: Différentes profondeurs
-- ============================================================================

\timing on

-- Profondeur 3
\echo 'Profondeur max: 3'
WITH RECURSIVE path AS (
  SELECT from_stop_id, to_stop_id, ARRAY[from_stop_id] as p, 1 as d
  FROM transfers
  WHERE from_stop_id IN (SELECT stop_id FROM stops WHERE stop_name LIKE '%Châtelet%' LIMIT 1)
  UNION ALL
  SELECT p.from_stop_id, t.to_stop_id, p.p || t.to_stop_id, p.d + 1
  FROM path p
  JOIN transfers t ON p.to_stop_id = t.from_stop_id
  WHERE NOT t.to_stop_id = ANY(p.p) AND p.d < 3
)
SELECT COUNT(*) as path_count FROM path;

-- Profondeur 5
\echo 'Profondeur max: 5'
WITH RECURSIVE path AS (
  SELECT from_stop_id, to_stop_id, ARRAY[from_stop_id] as p, 1 as d
  FROM transfers
  WHERE from_stop_id IN (SELECT stop_id FROM stops WHERE stop_name LIKE '%Châtelet%' LIMIT 1)
  UNION ALL
  SELECT p.from_stop_id, t.to_stop_id, p.p || t.to_stop_id, p.d + 1
  FROM path p
  JOIN transfers t ON p.to_stop_id = t.from_stop_id
  WHERE NOT t.to_stop_id = ANY(p.p) AND p.d < 5
)
SELECT COUNT(*) as path_count FROM path;

-- Profondeur 10
\echo 'Profondeur max: 10'
WITH RECURSIVE path AS (
  SELECT from_stop_id, to_stop_id, ARRAY[from_stop_id] as p, 1 as d
  FROM transfers
  WHERE from_stop_id IN (SELECT stop_id FROM stops WHERE stop_name LIKE '%Châtelet%' LIMIT 1)
  UNION ALL
  SELECT p.from_stop_id, t.to_stop_id, p.p || t.to_stop_id, p.d + 1
  FROM path p
  JOIN transfers t ON p.to_stop_id = t.from_stop_id
  WHERE NOT t.to_stop_id = ANY(p.p) AND p.d < 10
)
SELECT COUNT(*) as path_count FROM path;

\timing off

-- ============================================================================
-- EXPLAIN ANALYZE
-- ============================================================================

EXPLAIN ANALYZE
WITH RECURSIVE shortest_path AS (
  SELECT
    from_stop_id,
    to_stop_id,
    ARRAY[from_stop_id, to_stop_id] as path,
    COALESCE(min_transfer_time, 0) as cost,
    1 as depth
  FROM transfers
  WHERE from_stop_id IN (
    SELECT stop_id FROM stops WHERE stop_name LIKE '%Châtelet%' LIMIT 1
  )

  UNION

  SELECT
    sp.from_stop_id,
    t.to_stop_id,
    sp.path || t.to_stop_id,
    sp.cost + COALESCE(t.min_transfer_time, 0),
    sp.depth + 1
  FROM shortest_path sp
  JOIN transfers t ON sp.to_stop_id = t.from_stop_id
  WHERE NOT t.to_stop_id = ANY(sp.path)
    AND sp.depth < 10
)
SELECT
  (SELECT stop_name FROM stops WHERE stop_id = sp.from_stop_id) as from_stop,
  (SELECT stop_name FROM stops WHERE stop_id = sp.to_stop_id) as to_stop,
  sp.cost,
  sp.depth
FROM shortest_path sp
WHERE sp.to_stop_id IN (
  SELECT stop_id FROM stops WHERE stop_name LIKE '%Gare%'
)
ORDER BY sp.cost ASC
LIMIT 1;

-- Questions pour le rapport:
-- 1. Performance CTE récursive vs Cypher shortestPath?
-- 2. Combien de lignes scannées par la CTE?
-- 3. Hash Join ou Nested Loop?
-- 4. À partir de quelle profondeur la requête devient lente?
-- 5. Différence avec/sans pondération?
