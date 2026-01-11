-- ========================================
-- REQUÊTE 2 : QUANTIFIED PATTERNS (SQL)
-- ========================================
-- PostgreSQL n'a PAS de quantified patterns comme Cypher 25
-- On doit simuler avec WITH RECURSIVE + filtrage par nombre de hops

-- ========================================
-- CAS 1 : Exactement N escales (N=2)
-- ========================================

-- Simulation en SQL : filtrer par hops = 3 (2 escales)
WITH RECURSIVE flight_paths AS (
    SELECT
        f.source,
        f.target,
        ARRAY[f.source, f.target] AS path_codes,
        1 AS hops
    FROM flights f
    WHERE f.source = 'LAX'

    UNION ALL

    SELECT
        fp.source,
        f.target,
        fp.path_codes || f.target,
        fp.hops + 1
    FROM flight_paths fp
    JOIN flights f ON fp.target = f.source
    WHERE
        f.target != ALL(fp.path_codes)  -- Pas de cycle
        AND fp.hops < 10  -- Limite pour éviter explosion
)
SELECT
    path_codes AS route,
    hops
FROM flight_paths
WHERE
    target = 'JFK'
    AND hops = 3  -- Exactement 2 escales (3 vols)
ORDER BY path_codes
LIMIT 10;

-- ========================================
-- CAS 2 : Range de répétitions {n,m}
-- ========================================

-- Chemins avec 1 à 3 escales (2 à 4 vols)
WITH big_hubs AS (
    -- Identifier les grands hubs (>5000 vols)
    SELECT DISTINCT a.iata_code
    FROM airports a
    JOIN flights f ON a.iata_code = f.source
    GROUP BY a.iata_code
    HAVING COUNT(*) > 5000
),
flight_paths AS (
    SELECT
        f.source,
        f.target,
        f.departure_ts,
        f.arrival_ts,
        ARRAY[f.source, f.target] AS path_codes,
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
        fp.hops + 1
    FROM flight_paths fp
    JOIN flights f ON fp.target = f.source
    WHERE
        f.target != ALL(fp.path_codes)
        AND fp.hops < 4  -- Max 3 escales (4 vols)
        AND f.departure_ts >= fp.arrival_ts + INTERVAL '30 minutes'
)
SELECT
    fp.path_codes AS route,
    fp.hops AS escales
FROM flight_paths fp
WHERE
    fp.target = 'MIA'
    AND fp.hops BETWEEN 2 AND 4  -- 1 à 3 escales
    -- Vérifier que tous les intermédiaires sont des big hubs
    AND (
        SELECT bool_and(code = ANY(SELECT iata_code FROM big_hubs))
        FROM unnest(fp.path_codes[2:array_length(fp.path_codes,1)-1]) AS code
    )
ORDER BY fp.hops
LIMIT 5;

-- ========================================
-- CAS 3 : Tours (retour au point de départ)
-- ========================================

-- SQL ne supporte PAS REPEATABLE ELEMENTS nativement
-- On doit autoriser explicitement les revisites

WITH RECURSIVE flight_tours AS (
    SELECT
        f.source,
        f.target,
        f.source AS origin,  -- Garder l'origine
        ARRAY[f.id] AS path_flight_ids,  -- Suivre les vols, pas les aéroports
        ARRAY[f.source, f.target] AS path_codes,
        1 AS hops
    FROM flights f
    WHERE f.source = 'ATL'

    UNION ALL

    SELECT
        ft.source,
        f.target,
        ft.origin,
        ft.path_flight_ids || f.id,
        ft.path_codes || f.target,
        ft.hops + 1
    FROM flight_tours ft
    JOIN flights f ON ft.target = f.source
    WHERE
        f.id != ALL(ft.path_flight_ids)  -- Pas le même VOL deux fois
        AND ft.hops < 5  -- Limite
)
SELECT
    path_codes AS route,
    hops AS total_flights
FROM flight_tours
WHERE
    target = origin  -- Retour à l'origine
    AND hops >= 3  -- Au moins 3 vols
ORDER BY hops
LIMIT 10;

-- ========================================
-- CAS 4 : Au moins N passages par des hubs majeurs
-- ========================================

WITH major_hubs AS (
    SELECT DISTINCT a.iata_code
    FROM airports a
    JOIN flights f ON a.iata_code = f.source
    GROUP BY a.iata_code
    HAVING COUNT(*) > 3000
),
flight_paths AS (
    SELECT
        f.source,
        f.target,
        ARRAY[f.source, f.target] AS path_codes,
        1 AS hops
    FROM flights f
    WHERE f.source = 'SFO'

    UNION ALL

    SELECT
        fp.source,
        f.target,
        fp.path_codes || f.target,
        fp.hops + 1
    FROM flight_paths fp
    JOIN flights f ON fp.target = f.source
    WHERE
        f.target != ALL(fp.path_codes)
        AND fp.hops < 5
)
SELECT
    fp.path_codes AS route,
    -- Compter combien de nœuds sont des major hubs
    (
        SELECT count(*)
        FROM unnest(fp.path_codes[2:array_length(fp.path_codes,1)-1]) AS code
        WHERE code IN (SELECT iata_code FROM major_hubs)
    ) AS num_major_hubs,
    fp.hops
FROM flight_paths fp
WHERE
    fp.target = 'BOS'
    AND fp.hops BETWEEN 3 AND 5
    -- Au moins 2 hubs majeurs sur le chemin
    AND (
        SELECT count(*)
        FROM unnest(fp.path_codes[2:array_length(fp.path_codes,1)-1]) AS code
        WHERE code IN (SELECT iata_code FROM major_hubs)
    ) >= 2
ORDER BY fp.hops
LIMIT 10;

-- ========================================
-- CAS 5 : Combinaison avec contrainte de retard total
-- ========================================

WITH RECURSIVE flight_paths AS (
    SELECT
        f.source,
        f.target,
        ARRAY[f.source, f.target] AS path_codes,
        1 AS hops,
        f.delay AS total_delay
    FROM flights f
    WHERE f.source = 'DEN'

    UNION ALL

    SELECT
        fp.source,
        f.target,
        fp.path_codes || f.target,
        fp.hops + 1,
        fp.total_delay + f.delay
    FROM flight_paths fp
    JOIN flights f ON fp.target = f.source
    WHERE
        f.target != ALL(fp.path_codes)
        AND fp.hops < 3
        -- Pruning : retard total doit rester < 60
        AND fp.total_delay + f.delay <= 60.0
)
SELECT
    path_codes AS route,
    total_delay,
    hops
FROM flight_paths
WHERE
    target = 'LAX'
    AND hops BETWEEN 2 AND 3  -- 2-3 escales
ORDER BY total_delay
LIMIT 10;

-- ========================================
-- COMPARAISON : Flexibilité
-- ========================================

-- Cypher 25 {2,3} en une requête
-- SQL : doit filtrer par hops BETWEEN 2 AND 3

-- Version SQL pour chemins de 2 OU 3 hops
WITH RECURSIVE flight_paths AS (
    SELECT
        f.source,
        f.target,
        ARRAY[f.source, f.target] AS path_codes,
        1 AS hops
    FROM flights f
    WHERE f.source = 'LAX'

    UNION ALL

    SELECT
        fp.source,
        f.target,
        fp.path_codes || f.target,
        fp.hops + 1
    FROM flight_paths fp
    JOIN flights f ON fp.target = f.source
    WHERE
        f.target != ALL(fp.path_codes)
        AND fp.hops < 3  -- Limite à 3 hops max
)
SELECT
    path_codes AS route,
    hops
FROM flight_paths
WHERE
    target = 'NYC'
    AND hops IN (2, 3)  -- 2 OU 3 hops
ORDER BY hops, path_codes
LIMIT 20;

-- ========================================
-- ANALYSE DE PERFORMANCE
-- ========================================

-- Test : compter chemins de différentes longueurs

-- Tous les chemins de 2 à 4 hops entre top hubs
EXPLAIN ANALYZE
WITH RECURSIVE flight_paths AS (
    SELECT
        f.source, f.target,
        ARRAY[f.source] AS path,
        1 AS hops
    FROM flights f
    WHERE f.source IN ('ATL', 'DFW', 'ORD', 'DEN', 'LAX')

    UNION ALL

    SELECT
        fp.source, f.target,
        fp.path || f.target,
        fp.hops + 1
    FROM flight_paths fp
    JOIN flights f ON fp.target = f.source
    WHERE
        f.target != ALL(fp.path)
        AND fp.hops < 4
        AND f.target IN ('ATL', 'DFW', 'ORD', 'DEN', 'LAX')
)
SELECT
    hops,
    count(*) AS num_paths
FROM flight_paths
WHERE hops BETWEEN 2 AND 4
GROUP BY hops
ORDER BY hops;

-- ========================================
-- POINTS CLÉS POUR LE RAPPORT
-- ========================================

/*
1. SQL vs CYPHER QUANTIFIED PATTERNS :

   Cypher 25 : {2,3}
   - Concis, déclaratif
   - Un seul pattern

   SQL : hops BETWEEN 2 AND 3
   - Nécessite post-filtrage
   - Doit générer tous les chemins jusqu'à max, puis filtrer
   - Plus verbeux

2. LIMITATIONS SQL :

   a) Pas de REPEATABLE ELEMENTS natif
      - Doit suivre les IDs de relations manuellement
      - Plus complexe et verbeux

   b) Pas de quantifiers sur patterns
      - Seulement filtrage par nombre final de hops
      - Moins expressif

   c) Vérifications complexes requièrent sous-requêtes
      - "Au moins N hubs majeurs" → sous-requête avec unnest
      - Moins performant

3. AVANTAGES SQL :

   a) WITH RECURSIVE est standard SQL
      - Portable (PostgreSQL, MySQL 8+, SQL Server)
      - Bien documenté

   b) Plus explicite
      - On voit exactement ce qui se passe
      - Debugging plus facile

4. EXPRESSIVITÉ :

   Cypher 25 : 10-15 lignes pour cas complexe
   SQL : 30-50 lignes pour le même résultat

   Ratio : Cypher ~3x plus concis

5. PERFORMANCE :

   - Performance similaire si bien écrit
   - SQL peut être plus rapide sur agrégations simples
   - Cypher mieux optimisé pour traversées complexes

6. POUR LE RAPPORT :

   - Montrer code côte à côte (Cypher vs SQL)
   - Compter lignes de code (LOC)
   - Comparer temps d'exécution (EXPLAIN ANALYZE vs PROFILE)
   - Expliquer que quantifiers sont du "syntactic sugar"
   - Mais ce sugar améliore drastiquement la lisibilité
   - SQL peut faire la même chose, mais plus verbeux
*/
