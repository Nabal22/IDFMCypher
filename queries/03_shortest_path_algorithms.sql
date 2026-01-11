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
    -- Initialisation : vols directs depuis LAX
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

    -- BFS : explorer les vols suivants
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
        -- Pas de cycle
        f.target != ALL(sp.path_codes)
        -- Limiter la profondeur pour performance
        AND sp.hops < 10
        -- IMPORTANT : Ne pas explorer au-delà du premier chemin trouvé
        AND NOT EXISTS (
            SELECT 1 FROM shortest_path sp2
            WHERE sp2.target = 'JFK'
        )
)
-- Récupérer le premier chemin qui arrive à JFK
SELECT
    path_codes AS route,
    hops,
    total_distance,
    total_delay
FROM shortest_path
WHERE target = 'JFK'
ORDER BY hops
LIMIT 1;

-- Note : Cette approche n'est pas optimale en SQL car la condition
-- NOT EXISTS est évaluée APRÈS la génération des chemins, pas pendant.

-- ========================================
-- VERSION 2 : Dijkstra Manuel (pondéré par distance)
-- ========================================

-- Implémentation de Dijkstra en SQL pur
WITH RECURSIVE dijkstra AS (
    -- Initialisation : distance 0 pour LAX, infini pour les autres
    SELECT
        a.iata_code,
        CASE WHEN a.iata_code = 'LAX' THEN 0 ELSE 999999 END AS distance,
        ARRAY[a.iata_code] AS path,
        FALSE AS visited
    FROM airports a

    UNION ALL

    -- Relaxation des arêtes
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

-- Note : L'implémentation pure de Dijkstra en SQL est très complexe
-- et peu performante. Ci-dessus est une version simplifiée.

-- ========================================
-- VERSION 3 : Approche Pratique (BFS avec poids)
-- ========================================

-- Plus pratique : BFS qui garde trace du coût total
WITH RECURSIVE weighted_paths AS (
    SELECT
        f.source,
        f.target,
        f.departure_ts,
        f.arrival_ts,
        ARRAY[f.source, f.target] AS path_codes,
        1 AS hops,
        f.distance::NUMERIC AS total_cost,  -- Utiliser distance comme poids
        f.distance::NUMERIC AS min_cost_to_here  -- Coût minimum pour atteindre ce nœud
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
        wp.total_cost + f.distance  -- Nouveau coût
    FROM weighted_paths wp
    JOIN flights f ON wp.target = f.source
    WHERE
        f.target != ALL(wp.path_codes)
        AND wp.hops < 10
        -- Pruning : ne pas explorer si on a déjà un chemin moins cher vers ce nœud
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

-- ========================================
-- VERSION 4 : K Plus Courts Chemins
-- ========================================

-- Trouver les 5 plus courts chemins (par nombre de sauts)
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
        AND ap.hops < 5  -- Limiter pour éviter explosion
)
SELECT
    path_codes AS route,
    hops,
    total_distance
FROM all_paths
WHERE target = 'JFK'
ORDER BY hops, total_distance
LIMIT 5;

-- ========================================
-- VERSION 5 : Chemins avec Contraintes (temps de correspondance)
-- ========================================

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
        -- Contrainte : au moins 30 min de correspondance
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

-- ========================================
-- VERSION 6 : Comparaison de Métriques
-- ========================================

-- 6a. Chemin le plus court en distance
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

-- 6b. Chemin avec minimum de retard
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

-- ========================================
-- ANALYSE DE PERFORMANCE
-- ========================================

-- Benchmark : BFS simple
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

-- ========================================
-- EXTENSION PostgreSQL : pg_routing
-- ========================================

-- Note : PostgreSQL a une extension pg_routing pour graphes
-- Mais elle nécessite PostGIS et est orientée géospatial

-- Exemple (si pg_routing installé) :
/*
SELECT * FROM pgr_dijkstra(
    'SELECT id, source, target, distance AS cost FROM flights',
    (SELECT id FROM airports WHERE iata_code = 'LAX'),
    (SELECT id FROM airports WHERE iata_code = 'JFK'),
    directed := true
);
*/

-- ========================================
-- POINTS CLÉS POUR LE RAPPORT
-- ========================================

/*
1. SQL vs CYPHER pour SHORTEST PATH :

   SQL (WITH RECURSIVE) :
   - Peut implémenter BFS
   - Dijkstra manuel très complexe
   - Pas d'optimisation bidirectionnelle native
   - Performance : O(n^k) pour k sauts

   Cypher shortestPath :
   - BFS bidirectionnel optimisé
   - Une ligne de code
   - Performance : O(2*sqrt(n^k)) ≈ beaucoup mieux

2. LIMITATIONS SQL :

   a) Pas de BFS bidirectionnel natif
      - Doit explorer depuis source uniquement
      - Beaucoup plus de nœuds visités

   b) Dijkstra très difficile à implémenter
      - Nécessite sélection du nœud min non visité
      - Pas de queue de priorité en SQL
      - Performance médiocre

   c) Pas d'équivalent GDS
      - Pas de A*, Yen, Delta-Stepping
      - pg_routing existe mais limité

3. AVANTAGES SQL :

   a) WITH RECURSIVE est explicite
      - On voit exactement l'algorithme
      - Debugging plus facile

   b) Flexible pour contraintes custom
      - Facile d'ajouter WHERE conditions
      - Temps de correspondance, etc.

   c) Peut optimiser avec index
      - Index sur (source, target)
      - Peut accélérer les JOINs

4. PERFORMANCE ATTENDUE :

   Pour LAX → JFK (~2500 miles, ~3 hops) :

   SQL BFS :
   - Temps : 200-500ms
   - Lignes explorées : ~50,000
   - Algorithm : Recursive CTE Scan

   Cypher shortestPath :
   - Temps : 10-50ms
   - db hits : 1,000-5,000
   - Algorithm : BidirectionalShortestPath

   Speedup : Cypher ~10x plus rapide

5. EXPLAIN ANALYZE vs PROFILE :

   SQL EXPLAIN ANALYZE montre :
   - CTE Scan (récursif)
   - Hash Join pour flights
   - Rows : nombre total généré
   - Planning time vs Execution time

   Cypher PROFILE montre :
   - ShortestPath operator
   - BidirectionalTraversal
   - db hits
   - Algorithme utilisé (BFS bidirectionnel)

6. POUR LE RAPPORT :

   a) Montrer code SQL vs Cypher côte à côte
      - SQL : 30-40 lignes pour Dijkstra
      - Cypher : 1-2 lignes

   b) Comparer temps d'exécution
      - EXPLAIN ANALYZE vs PROFILE
      - Calculer speedup

   c) Expliquer pourquoi Cypher est plus rapide
      - BFS bidirectionnel
      - Optimisations natives
      - Structures de données dédiées

   d) Mentionner pg_routing comme alternative
      - Mais nécessite PostGIS
      - Orienté géospatial

   e) Conclusion :
      - SQL peut faire des shortest paths
      - Mais beaucoup moins performant
      - Cypher/Neo4j conçu pour ça
      - Utiliser le bon outil pour le bon problème
*/
