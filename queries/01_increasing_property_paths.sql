-- ========================================
-- REQUÊTE 1 : INCREASING PROPERTY PATHS (SQL)
-- ========================================
-- Version PostgreSQL avec WITH RECURSIVE
-- Comparaison avec Cypher 5 et Cypher 25

-- ========================================
-- VERSION 1 : WITH RECURSIVE + Post-filtering
-- ========================================
-- Similaire à Cypher 5 : génère tous les chemins puis filtre
-- PROBLÈME : Explosion combinatoire avant le filtrage

WITH RECURSIVE flight_paths AS (
    -- Cas de base : vols directs depuis LAX
    SELECT
        f.id AS flight_id,
        f.source,
        f.target,
        f.departure_ts,
        f.arrival_ts,
        f.distance,
        f.delay,
        ARRAY[f.source] AS path_codes,
        ARRAY[f.delay] AS path_delays,
        1 AS hops,
        f.delay AS total_delay
    FROM flights f
    WHERE f.source = 'LAX'

    UNION ALL

    -- Récursion : ajouter un vol
    SELECT
        f.id,
        fp.source,
        f.target,
        fp.departure_ts,
        f.arrival_ts,
        fp.distance + f.distance,
        f.delay,
        fp.path_codes || f.target,
        fp.path_delays || f.delay,
        fp.hops + 1,
        fp.total_delay + f.delay
    FROM flight_paths fp
    JOIN flights f ON fp.target = f.source
    WHERE
        -- Éviter les cycles
        f.target != ALL(fp.path_codes)
        -- Limiter la profondeur (2-4 escales)
        AND fp.hops < 4
        -- Temps de correspondance minimum
        AND f.departure_ts >= fp.arrival_ts + INTERVAL '30 minutes'
)
-- FILTRAGE POST-TRAVERSÉE (comme Cypher 5)
SELECT
    path_codes || target AS route,
    path_delays AS delays,
    hops,
    total_delay
FROM flight_paths
WHERE
    target = 'JFK'
    -- Vérifier que tous les retards sont croissants
    AND (
        -- Fonction personnalisée pour vérifier la croissance
        SELECT bool_and(
            CASE
                WHEN i = 1 THEN true
                ELSE path_delays[i] > path_delays[i-1]
            END
        )
        FROM generate_series(1, array_length(path_delays, 1)) AS i
    )
ORDER BY hops, total_delay
LIMIT 10;

-- ========================================
-- VERSION 2 : WITH RECURSIVE + Pruning Précoce
-- ========================================
-- Plus proche de Cypher 25 : élimine les chemins invalides tôt
-- MEILLEURE PERFORMANCE

WITH RECURSIVE flight_paths AS (
    -- Cas de base : vols directs depuis LAX
    SELECT
        f.source,
        f.target,
        f.departure_ts,
        f.arrival_ts,
        ARRAY[f.source, f.target] AS path_codes,
        ARRAY[f.delay] AS path_delays,
        1 AS hops,
        f.delay AS total_delay,
        f.delay AS last_delay  -- Garder trace du dernier retard
    FROM flights f
    WHERE f.source = 'LAX'

    UNION ALL

    -- Récursion avec PRUNING pendant la traversée
    SELECT
        fp.source,
        f.target,
        fp.departure_ts,
        f.arrival_ts,
        fp.path_codes || f.target,
        fp.path_delays || f.delay,
        fp.hops + 1,
        fp.total_delay + f.delay,
        f.delay
    FROM flight_paths fp
    JOIN flights f ON fp.target = f.source
    WHERE
        f.target != ALL(fp.path_codes)
        AND fp.hops < 4
        AND f.departure_ts >= fp.arrival_ts + INTERVAL '30 minutes'
        -- PRUNING : Retard doit être > au précédent
        AND f.delay > fp.last_delay  -- CLEF : Filtrage précoce !
)
SELECT
    path_codes AS route,
    path_delays AS delays,
    hops,
    total_delay
FROM flight_paths
WHERE target = 'JFK'
ORDER BY hops, total_delay
LIMIT 10;

-- ========================================
-- VERSION 3 : Distance croissante
-- ========================================

WITH RECURSIVE flight_paths AS (
    SELECT
        f.source,
        f.target,
        ARRAY[f.source, f.target] AS path_codes,
        ARRAY[f.distance] AS path_distances,
        1 AS hops,
        f.distance AS last_distance
    FROM flights f
    WHERE f.source = 'ATL'

    UNION ALL

    SELECT
        fp.source,
        f.target,
        fp.path_codes || f.target,
        fp.path_distances || f.distance,
        fp.hops + 1,
        f.distance
    FROM flight_paths fp
    JOIN flights f ON fp.target = f.source
    WHERE
        f.target != ALL(fp.path_codes)
        AND fp.hops < 4
        AND f.distance > fp.last_distance  -- Distance croissante
)
SELECT
    path_codes AS route,
    path_distances AS distances,
    hops
FROM flight_paths
WHERE target = 'SEA'
ORDER BY hops
LIMIT 5;

-- ========================================
-- VERSION 4 : Temps croissants (correspondances valides)
-- ========================================

WITH RECURSIVE flight_paths AS (
    SELECT
        f.source,
        f.target,
        f.departure_ts,
        f.arrival_ts,
        ARRAY[f.source, f.target] AS path_codes,
        ARRAY[ROW(f.departure_ts, f.arrival_ts)] AS path_times,
        1 AS hops
    FROM flights f
    WHERE f.source = 'LAX'

    UNION ALL

    SELECT
        fp.source,
        f.target,
        fp.departure_ts,
        f.arrival_ts,
        fp.path_codes || f.target,
        fp.path_times || ROW(f.departure_ts, f.arrival_ts),
        fp.hops + 1
    FROM flight_paths fp
    JOIN flights f ON fp.target = f.source
    WHERE
        f.target != ALL(fp.path_codes)
        AND fp.hops < 3
        -- Correspondance valide : au moins 30 min entre vols
        AND f.departure_ts >= fp.arrival_ts + INTERVAL '30 minutes'
)
SELECT
    path_codes AS route,
    hops
FROM flight_paths
WHERE target = 'BOS'
ORDER BY hops
LIMIT 5;

-- ========================================
-- ANALYSE DE PERFORMANCE
-- ========================================

-- Test sur sous-graphe (top 10 hubs)
-- Comparaison post-filtering vs pruning précoce

-- Version POST-FILTERING (lente)
EXPLAIN ANALYZE
WITH RECURSIVE flight_paths AS (
    SELECT
        f.source, f.target,
        ARRAY[f.source] AS path_codes,
        ARRAY[f.delay] AS path_delays,
        1 AS hops
    FROM flights f
    WHERE f.source IN ('LAX', 'ATL', 'ORD', 'DEN', 'DFW', 'JFK', 'SFO', 'LAS', 'PHX', 'IAH')

    UNION ALL

    SELECT
        fp.source, f.target,
        fp.path_codes || f.target,
        fp.path_delays || f.delay,
        fp.hops + 1
    FROM flight_paths fp
    JOIN flights f ON fp.target = f.source
    WHERE
        f.target != ALL(fp.path_codes)
        AND fp.hops < 3
        AND f.target IN ('LAX', 'ATL', 'ORD', 'DEN', 'DFW', 'JFK', 'SFO', 'LAS', 'PHX', 'IAH')
)
SELECT count(*)
FROM flight_paths
WHERE (
    SELECT bool_and(
        CASE WHEN i = 1 THEN true ELSE path_delays[i] > path_delays[i-1] END
    )
    FROM generate_series(1, array_length(path_delays, 1)) AS i
);

-- Version PRUNING PRÉCOCE (rapide)
EXPLAIN ANALYZE
WITH RECURSIVE flight_paths AS (
    SELECT
        f.source, f.target,
        ARRAY[f.source] AS path_codes,
        ARRAY[f.delay] AS path_delays,
        1 AS hops,
        f.delay AS last_delay
    FROM flights f
    WHERE f.source IN ('LAX', 'ATL', 'ORD', 'DEN', 'DFW', 'JFK', 'SFO', 'LAS', 'PHX', 'IAH')

    UNION ALL

    SELECT
        fp.source, f.target,
        fp.path_codes || f.target,
        fp.path_delays || f.delay,
        fp.hops + 1,
        f.delay
    FROM flight_paths fp
    JOIN flights f ON fp.target = f.source
    WHERE
        f.target != ALL(fp.path_codes)
        AND fp.hops < 3
        AND f.target IN ('LAX', 'ATL', 'ORD', 'DEN', 'DFW', 'JFK', 'SFO', 'LAS', 'PHX', 'IAH')
        AND f.delay > fp.last_delay  -- PRUNING ICI
)
SELECT count(*) FROM flight_paths;

-- ========================================
-- POINTS CLÉS POUR LE RAPPORT
-- ========================================

/*
1. COMPARAISON SQL vs CYPHER :

   SQL Version 1 (post-filtering) ≈ Cypher 5 :
   - Génère tous les chemins puis filtre
   - Coût : O(n^k) chemins générés
   - Performance : Lente sur grands graphes

   SQL Version 2 (pruning précoce) ≈ Cypher 25 allReduce :
   - Filtre pendant la récursion
   - Coût réduit : beaucoup de branches élimées tôt
   - Performance : Significativement meilleure

2. AVANTAGES SQL :
   - WITH RECURSIVE est plus explicite
   - Facile de voir où le pruning se fait
   - Moins "magique" que allReduce

3. INCONVÉNIENTS SQL :
   - Plus verbeux (3x plus de code)
   - Moins déclaratif
   - Arrays en PostgreSQL plus lourds que listes Cypher

4. RÉSULTATS ATTENDUS :
   - Version 1 : ~10-50x plus lente que version 2
   - Version 2 : Performance similaire à Cypher 25
   - Cypher reste plus lisible

5. PLANS D'EXÉCUTION (EXPLAIN ANALYZE) :
   - Version 1 : CTE Scan → Aggregate (bool_and) par ligne
   - Version 2 : CTE Scan avec moins de lignes intermédiaires
   - Regarder "Rows Removed by Filter" : beaucoup moins en v2

6. POUR LE RAPPORT :
   - Montrer les deux EXPLAIN ANALYZE côte à côte
   - Comparer temps d'exécution et lignes générées
   - Expliquer que SQL CAN faire du pruning précoce
   - Mais Cypher 25 le fait plus élégamment
*/
