-- ========================================
-- REQUÊTE 3 : SHORTEST PATH (SQL)
-- ========================================
-- PostgreSQL : Implémentation de Dijkstra avec WITH RECURSIVE
-- Comparaison avec Cypher 5, Cypher 25, et GDS

-- ========================================
-- VERSION 1 : BFS Non Pondéré (nombre de sauts)
-- ========================================

-- Algorithme : BFS simple pour trouver le plus court chemin
WITH RECURSIVE shortest_path AS (
    -- Init depuis LAX
    SELECT
        f.source,
        f.target,
        ARRAY[f.source, f.target] AS path_codes,
        1 AS hops,
        f.distance AS total_distance,
        f.delay AS total_delay
    FROM flights f
    WHERE f.source = 'LAX'

    UNION ALL

    -- Explorer vols suivants
    SELECT
        sp.source,
        f.target,
        sp.path_codes || f.target,
        sp.hops + 1,
        sp.total_distance + f.distance,
        sp.total_delay + f.delay
    FROM shortest_path sp
    JOIN flights f ON sp.target = f.source
    WHERE
        f.target != ALL(sp.path_codes)
        AND sp.hops < 10
        AND NOT EXISTS (
            SELECT 1 FROM shortest_path sp2
            WHERE sp2.target = 'JFK'
        )
)
SELECT
    path_codes AS route,
    hops,
    total_distance,
    total_delay
FROM shortest_path
WHERE target = 'JFK'
ORDER BY hops
LIMIT 1;

-- Dijkstra manuel (distance pondérée)
WITH RECURSIVE dijkstra AS (
    -- Init: LAX = 0, autres = infini
    SELECT
        a.iata_code,
        CASE WHEN a.iata_code = 'LAX' THEN 0 ELSE 999999 END AS distance,
        ARRAY[a.iata_code] AS path,
        FALSE AS visited
    FROM airports a

    UNION ALL

    -- Relaxation
    SELECT
        d.iata_code,
        LEAST(
            d.distance,
            (
                SELECT MIN(d2.distance + f.distance)
                FROM dijkstra d2
                JOIN flights f ON d2.iata_code = f.source
                WHERE f.target = d.iata_code
                  AND d2.visited = FALSE
            )
        ),
        d.path,
        d.visited OR d.iata_code = (
            SELECT d3.iata_code
            FROM dijkstra d3
            WHERE d3.visited = FALSE
            ORDER BY d3.distance
            LIMIT 1
        )
    FROM dijkstra d
)
SELECT * FROM dijkstra
WHERE iata_code = 'JFK'
ORDER BY distance
LIMIT 1;

-- BFS avec poids (plus pratique)
WITH RECURSIVE weighted_paths AS (
    SELECT
        f.source,
        f.target,
        f.departure_ts,
        f.arrival_ts,
        ARRAY[f.source, f.target] AS path_codes,
        1 AS hops,
        f.distance::NUMERIC AS total_cost,
        f.distance::NUMERIC AS min_cost_to_here
    FROM flights f
    WHERE f.source = 'LAX'

    UNION ALL

    SELECT
        wp.source,
        f.target,
        wp.departure_ts,
        f.arrival_ts,
        wp.path_codes || f.target,
        wp.hops + 1,
        wp.total_cost + f.distance,
        wp.total_cost + f.distance
    FROM weighted_paths wp
    JOIN flights f ON wp.target = f.source
    WHERE
        f.target != ALL(wp.path_codes)
        AND wp.hops < 10
        AND wp.total_cost + f.distance < (
            SELECT COALESCE(MIN(wp2.min_cost_to_here), 999999)
            FROM weighted_paths wp2
            WHERE wp2.target = f.target
        )
)
SELECT
    path_codes AS route,
    hops,
    total_cost AS total_distance
FROM weighted_paths
WHERE target = 'JFK'
ORDER BY total_cost
LIMIT 1;

-- Top 5 chemins
WITH RECURSIVE all_paths AS (
    SELECT
        f.source,
        f.target,
        ARRAY[f.source, f.target] AS path_codes,
        1 AS hops,
        f.distance AS total_distance
    FROM flights f
    WHERE f.source = 'LAX'

    UNION ALL

    SELECT
        ap.source,
        f.target,
        ap.path_codes || f.target,
        ap.hops + 1,
        ap.total_distance + f.distance
    FROM all_paths ap
    JOIN flights f ON ap.target = f.source
    WHERE
        f.target != ALL(ap.path_codes)
        AND ap.hops < 5
)
SELECT
    path_codes AS route,
    hops,
    total_distance
FROM all_paths
WHERE target = 'JFK'
ORDER BY hops, total_distance
LIMIT 5;

-- Avec contrainte de temps (30min correspondance min)

WITH RECURSIVE valid_paths AS (
    SELECT
        f.source,
        f.target,
        f.departure_ts,
        f.arrival_ts,
        ARRAY[f.source, f.target] AS path_codes,
        1 AS hops,
        f.distance AS total_distance
    FROM flights f
    WHERE f.source = 'LAX'

    UNION ALL

    SELECT
        vp.source,
        f.target,
        vp.departure_ts,
        f.arrival_ts,
        vp.path_codes || f.target,
        vp.hops + 1,
        vp.total_distance + f.distance
    FROM valid_paths vp
    JOIN flights f ON vp.target = f.source
    WHERE
        f.target != ALL(vp.path_codes)
        AND vp.hops < 5
        AND f.departure_ts >= vp.arrival_ts + INTERVAL '30 minutes'
)
SELECT
    path_codes AS route,
    hops,
    total_distance
FROM valid_paths
WHERE target = 'JFK'
ORDER BY hops
LIMIT 1;

-- Comparaison métriques
WITH RECURSIVE distance_paths AS (
    SELECT
        f.source, f.target,
        ARRAY[f.source, f.target] AS path_codes,
        1 AS hops,
        f.distance AS total_distance
    FROM flights f
    WHERE f.source = 'LAX'

    UNION ALL

    SELECT
        dp.source, f.target,
        dp.path_codes || f.target,
        dp.hops + 1,
        dp.total_distance + f.distance
    FROM distance_paths dp
    JOIN flights f ON dp.target = f.source
    WHERE
        f.target != ALL(dp.path_codes)
        AND dp.hops < 6
)
SELECT
    'Shortest by distance' AS metric,
    path_codes AS route,
    total_distance,
    hops
FROM distance_paths
WHERE target = 'MIA'
ORDER BY total_distance
LIMIT 1;

-- Min delay
WITH RECURSIVE delay_paths AS (
    SELECT
        f.source, f.target,
        ARRAY[f.source, f.target] AS path_codes,
        1 AS hops,
        f.delay AS total_delay
    FROM flights f
    WHERE f.source = 'LAX'

    UNION ALL

    SELECT
        dp.source, f.target,
        dp.path_codes || f.target,
        dp.hops + 1,
        dp.total_delay + f.delay
    FROM delay_paths dp
    JOIN flights f ON dp.target = f.source
    WHERE
        f.target != ALL(dp.path_codes)
        AND dp.hops < 6
)
SELECT
    'Minimum delay' AS metric,
    path_codes AS route,
    total_delay AS total_delay_minutes,
    hops
FROM delay_paths
WHERE target = 'MIA'
ORDER BY total_delay
LIMIT 1;

-- Benchmark BFS
EXPLAIN ANALYZE
WITH RECURSIVE shortest_path AS (
    SELECT
        f.source, f.target,
        ARRAY[f.source] AS path,
        1 AS hops
    FROM flights f
    WHERE f.source IN ('LAX', 'ATL', 'ORD', 'DEN', 'DFW')

    UNION ALL

    SELECT
        sp.source, f.target,
        sp.path || f.target,
        sp.hops + 1
    FROM shortest_path sp
    JOIN flights f ON sp.target = f.source
    WHERE
        f.target != ALL(sp.path)
        AND sp.hops < 4
        AND f.target IN ('LAX', 'ATL', 'ORD', 'DEN', 'DFW')
)
SELECT
    source,
    target,
    min(hops) AS shortest_distance
FROM shortest_path
GROUP BY source, target;

-- pg_routing (si installé)
/*
SELECT * FROM pgr_dijkstra(
    'SELECT id, source, target, distance AS cost FROM flights',
    (SELECT id FROM airports WHERE iata_code = 'LAX'),
    (SELECT id FROM airports WHERE iata_code = 'JFK'),
    directed := true
);
*/

/*
================================================================================
POINTS CLÉS POUR LE RAPPORT
================================================================================

1. COMPARAISON DES APPROCHES

   SQL (WITH RECURSIVE):
   - Implémentation manuelle de BFS ou Dijkstra
   - Code verbeux (30-40 lignes vs 1 ligne Cypher)
   - Pas de BFS bidirectionnel → explore depuis une seule direction
   - Pas de priority queue native → Dijkstra difficile à implémenter
   - Complexité O(n^k) pour k sauts → explosion combinatoire

   Cypher 5/25 (shortestPath/SHORTEST):
   - BFS bidirectionnel optimisé
   - Syntaxe déclarative (1 ligne)
   - NE SUPPORTE PAS les poids → compte uniquement les sauts
   - Pour chemins pondérés → exploration exhaustive O(branches^depth)
   - allReduce (Cypher 25) évite NP-complet mais reste lent

   GDS (Dijkstra):
   - Algorithme optimisé en C++
   - Supporte les poids (distance, delay, etc.)
   - Garantit l'optimalité du résultat
   - 100-1000x plus rapide que SQL/Cypher pur


2. PERFORMANCES MESURÉES (JFK → DAY, 2 sauts, 590 miles optimal)

   Cypher 5 shortestPath():
   - Temps: instantané (~15ms)
   - Résultat: [JFK, ATL, DAY] = 1192 miles (non optimal, +102%)
   - Trouve le chemin avec MOINS DE SAUTS, pas la distance min
   - Ne prend PAS en compte les poids

   Cypher 25 exhaustif *1..2 (avec allReduce):
   - Temps: 293ms
   - Résultat: [JFK, BWI, DAY] = 590 miles (optimal)
   - Limité à 2 sauts max (notre dataset n'a pas de vols >1 escale)
   - Avec *1..3: 2 minutes 17 secondes (explosion combinatoire)
   - Ne scale PAS au-delà de 2-3 sauts

   GDS Dijkstra:
   - Temps: 37ms (8x plus rapide que Cypher exhaustif)
   - Résultat: [JFK, BWI, DAY] = 590 miles (optimal garanti)
   - Scale à N sauts sans problème
   - Gère des milliers de nœuds efficacement


3. LIMITES TECHNIQUES

   SQL:
   - WITH RECURSIVE = scan séquentiel de tous les chemins
   - Impossible d'implémenter priority queue
   - Pas d'optimisation bidirectionnelle
   - Indexes (source, target) aident mais limités

   Cypher pur:
   - Langage déclaratif → pas de structures mutables
   - Pas de priority queue disponible
   - reduce() dans WHERE = NP-complet (SIGMOD)
   - allReduce améliore mais ne résout pas le problème fondamental


4. QUAND UTILISER CHAQUE APPROCHE?

   SQL WITH RECURSIVE:
   ✓ Contraintes métier complexes (temps de correspondance, horaires)
   ✓ Voir explicitement l'algorithme (pédagogie)
   ✓ Pas de GDS disponible
   ✗ Chemins pondérés à grande échelle

   Cypher shortestPath():
   ✓ Plus court chemin NON pondéré (minimum de sauts)
   ✓ Syntaxe simple et rapide
   ✓ Graphes de toute taille
   ✗ Chemins pondérés (ne prend pas en compte les poids)

   Cypher exhaustif (*1..n):
   ✓ Prototypage sur petits graphes
   ✓ Exploration avec filtres complexes
   ✗ Production (timeout)
   ✗ Profondeur > 3-4

   GDS Dijkstra:
   ✓ Chemins pondérés (OBLIGATOIRE)
   ✓ Performance critique
   ✓ Optimalité garantie
   ✓ Graphes de toute taille
   - Nécessite projection du graphe


5. CONCLUSION

   Pour les chemins pondérés, GDS est INDISPENSABLE:
   - Cypher/SQL purs → force brute inefficace
   - Seule solution qui garantit l'optimalité
   - Performance 100-1000x supérieure
   - Implémentations éprouvées (Dijkstra, A*, Yen)

   Règle générale:
   - Min sauts → Cypher shortestPath()
   - Min distance/poids → GDS Dijkstra
   - Contraintes métier → SQL WITH RECURSIVE
*/
