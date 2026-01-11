-- ========================================
-- Requêtes de Validation Post-Import PostgreSQL
-- ========================================

-- 1. STATISTIQUES GÉNÉRALES
-- ========================================

-- Compter tous les enregistrements
SELECT 'Airlines' AS table_name, COUNT(*) AS count FROM airlines
UNION ALL
SELECT 'Airports', COUNT(*) FROM airports
UNION ALL
SELECT 'Flights', COUNT(*) FROM flights
ORDER BY table_name;

-- Vue d'ensemble du schéma
SELECT
    table_name,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
ORDER BY table_name, ordinal_position;


-- 2. VÉRIFICATIONS DE QUALITÉ DES DONNÉES
-- ========================================

-- Vérifier qu'il n'y a pas de vols vers le même aéroport
SELECT COUNT(*) as self_loops
FROM flights
WHERE source = target;
-- Résultat attendu: 0

-- Vérifier qu'il n'y a pas de valeurs nulles dans les timestamps
SELECT COUNT(*) as null_timestamps
FROM flights
WHERE departure_ts IS NULL OR arrival_ts IS NULL;
-- Résultat attendu: 0

-- Vérifier la distribution des retards
SELECT
    MIN(delay) as min_delay,
    MAX(delay) as max_delay,
    AVG(delay) as avg_delay,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delay) as median_delay,
    STDDEV(delay) as stddev_delay
FROM flights;


-- 3. ANALYSE DU RÉSEAU
-- ========================================

-- Top 10 des aéroports par nombre de départs
SELECT
    a.iata_code,
    a.city,
    a.state,
    COUNT(f.id) as departures
FROM airports a
JOIN flights f ON a.iata_code = f.source
GROUP BY a.iata_code, a.city, a.state
ORDER BY departures DESC
LIMIT 10;

-- Top 10 des aéroports par nombre d'arrivées
SELECT
    a.iata_code,
    a.city,
    a.state,
    COUNT(f.id) as arrivals
FROM airports a
JOIN flights f ON a.iata_code = f.target
GROUP BY a.iata_code, a.city, a.state
ORDER BY arrivals DESC
LIMIT 10;

-- Top 10 des hubs (utilise la vue)
SELECT
    iata_code,
    city,
    state,
    departures,
    arrivals,
    total_flights
FROM airport_stats
ORDER BY total_flights DESC
LIMIT 10;

-- Distribution des compagnies
SELECT
    al.iata_code,
    al.name,
    COUNT(f.id) as flights
FROM airlines al
LEFT JOIN flights f ON al.iata_code = f.airline
GROUP BY al.iata_code, al.name
ORDER BY flights DESC;


-- 4. ANALYSE TEMPORELLE
-- ========================================

-- Distribution des vols par jour
SELECT
    EXTRACT(DAY FROM departure_ts) as day,
    COUNT(*) as flights
FROM flights
GROUP BY day
ORDER BY day;

-- Heures de pointe (par heure de départ)
SELECT
    EXTRACT(HOUR FROM departure_ts) as hour,
    COUNT(*) as flights
FROM flights
GROUP BY hour
ORDER BY hour;

-- Vols les plus longs (par durée)
SELECT
    source,
    target,
    src.city as from_city,
    dst.city as to_city,
    airline,
    departure_ts,
    arrival_ts,
    arrival_ts - departure_ts AS duration,
    distance
FROM flights f
JOIN airports src ON f.source = src.iata_code
JOIN airports dst ON f.target = dst.iata_code
ORDER BY duration DESC
LIMIT 10;


-- 5. ANALYSE GÉOGRAPHIQUE
-- ========================================

-- Vols les plus longs par distance
SELECT
    f.source,
    f.target,
    src.city as from_city,
    dst.city as to_city,
    f.distance as distance_miles
FROM flights f
JOIN airports src ON f.source = src.iata_code
JOIN airports dst ON f.target = dst.iata_code
ORDER BY distance_miles DESC
LIMIT 10;

-- Aéroports les plus au nord/sud/est/ouest
(SELECT 'Northernmost' as type, iata_code, city, latitude, longitude
 FROM airports ORDER BY latitude DESC LIMIT 1)
UNION ALL
(SELECT 'Southernmost', iata_code, city, latitude, longitude
 FROM airports ORDER BY latitude ASC LIMIT 1)
UNION ALL
(SELECT 'Easternmost', iata_code, city, latitude, longitude
 FROM airports ORDER BY longitude DESC LIMIT 1)
UNION ALL
(SELECT 'Westernmost', iata_code, city, latitude, longitude
 FROM airports ORDER BY longitude ASC LIMIT 1);

-- Distance entre aéroports (formule haversine approximative)
-- Note: PostgreSQL peut avoir l'extension PostGIS pour des calculs plus précis
SELECT
    f.source,
    f.target,
    f.distance as reported_distance,
    ROUND(
        111.045 * DEGREES(ACOS(
            COS(RADIANS(src.latitude))
            * COS(RADIANS(dst.latitude))
            * COS(RADIANS(src.longitude - dst.longitude))
            + SIN(RADIANS(src.latitude))
            * SIN(RADIANS(dst.latitude))
        )) * 0.621371  -- km to miles
    ) as calculated_distance_miles
FROM flights f
JOIN airports src ON f.source = src.iata_code
JOIN airports dst ON f.target = dst.iata_code
LIMIT 10;


-- 6. ANALYSE DES RETARDS
-- ========================================

-- Top 10 des vols les plus en retard
SELECT
    source,
    target,
    airline,
    departure_ts,
    delay as delay_minutes
FROM flights
WHERE delay > 0
ORDER BY delay DESC
LIMIT 10;

-- Top 10 des vols les plus en avance
SELECT
    source,
    target,
    airline,
    departure_ts,
    delay as early_minutes
FROM flights
WHERE delay < 0
ORDER BY delay ASC
LIMIT 10;

-- Retard moyen par compagnie (utilise la vue)
SELECT * FROM airline_stats
ORDER BY avg_delay DESC;

-- Retard moyen par aéroport de départ
SELECT
    a.iata_code,
    a.city,
    COUNT(f.id) as flights,
    AVG(f.delay) as avg_delay
FROM airports a
JOIN flights f ON a.iata_code = f.source
GROUP BY a.iata_code, a.city
HAVING COUNT(f.id) >= 100  -- Au moins 100 vols
ORDER BY avg_delay DESC
LIMIT 10;

-- Distribution des retards par tranche
SELECT
    CASE
        WHEN delay < -15 THEN 'Very Early (< -15 min)'
        WHEN delay >= -15 AND delay < 0 THEN 'Slightly Early (0 to -15 min)'
        WHEN delay >= 0 AND delay < 15 THEN 'On Time (0 to 15 min)'
        WHEN delay >= 15 AND delay < 30 THEN 'Delayed (15-30 min)'
        WHEN delay >= 30 AND delay < 60 THEN 'Delayed (30-60 min)'
        WHEN delay >= 60 THEN 'Very Delayed (> 60 min)'
    END as delay_category,
    COUNT(*) as flights,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM flights), 2) as percentage
FROM flights
GROUP BY delay_category
ORDER BY
    CASE
        WHEN delay < -15 THEN 1
        WHEN delay >= -15 AND delay < 0 THEN 2
        WHEN delay >= 0 AND delay < 15 THEN 3
        WHEN delay >= 15 AND delay < 30 THEN 4
        WHEN delay >= 30 AND delay < 60 THEN 5
        WHEN delay >= 60 THEN 6
    END;


-- 7. CONNECTIVITÉ
-- ========================================

-- Aéroports isolés (pas de connexion)
SELECT a.iata_code, a.city
FROM airports a
LEFT JOIN flights f1 ON a.iata_code = f1.source
LEFT JOIN flights f2 ON a.iata_code = f2.target
WHERE f1.id IS NULL AND f2.id IS NULL;
-- Résultat attendu: vide

-- Nombre de destinations directes par aéroport
SELECT
    a.iata_code,
    a.city,
    COUNT(DISTINCT f.target) as direct_destinations
FROM airports a
LEFT JOIN flights f ON a.iata_code = f.source
GROUP BY a.iata_code, a.city
ORDER BY direct_destinations DESC
LIMIT 10;

-- Routes les plus fréquentées (paires d'aéroports, bidirectionnel)
SELECT
    CASE WHEN a1.iata_code < a2.iata_code THEN a1.iata_code ELSE a2.iata_code END as airport1,
    CASE WHEN a1.iata_code < a2.iata_code THEN a2.iata_code ELSE a1.iata_code END as airport2,
    CASE WHEN a1.iata_code < a2.iata_code THEN a1.city ELSE a2.city END as city1,
    CASE WHEN a1.iata_code < a2.iata_code THEN a2.city ELSE a1.city END as city2,
    COUNT(*) as total_flights
FROM flights f
JOIN airports a1 ON f.source = a1.iata_code
JOIN airports a2 ON f.target = a2.iata_code
GROUP BY airport1, airport2, city1, city2
ORDER BY total_flights DESC
LIMIT 10;


-- 8. CHEMINS AVEC RECURSIVE CTE
-- ========================================

-- Exemple: Tous les chemins possibles LAX -> JFK avec max 2 escales
WITH RECURSIVE flight_paths AS (
    -- Cas de base: vols directs depuis LAX
    SELECT
        source,
        target,
        airline,
        departure_ts,
        arrival_ts,
        ARRAY[source, target] as path,
        1 as hops,
        distance as total_distance,
        delay as total_delay
    FROM flights
    WHERE source = 'LAX'

    UNION ALL

    -- Récursion: ajouter un vol
    SELECT
        fp.source,
        f.target,
        f.airline,
        fp.departure_ts,
        f.arrival_ts,
        fp.path || f.target,
        fp.hops + 1,
        fp.total_distance + f.distance,
        fp.total_delay + f.delay
    FROM flight_paths fp
    JOIN flights f ON fp.target = f.source
    WHERE
        f.target != ALL(fp.path)  -- Pas de cycle
        AND fp.hops < 3  -- Maximum 2 escales
        AND f.departure_ts >= fp.arrival_ts + INTERVAL '30 minutes'  -- Temps de correspondance
)
SELECT
    path,
    hops,
    total_distance,
    total_delay,
    departure_ts,
    arrival_ts,
    arrival_ts - departure_ts as total_duration
FROM flight_paths
WHERE target = 'JFK'
ORDER BY hops, total_distance
LIMIT 10;


-- 9. PERFORMANCE ET INDEX
-- ========================================

-- Taille des tables
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) -
                   pg_relation_size(schemaname||'.'||tablename)) AS index_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Liste des index
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

-- Statistiques d'utilisation des index (nécessite de faire quelques requêtes avant)
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;


-- 10. EXEMPLES DE VOLS DÉTAILLÉS
-- ========================================

-- 10 vols aléatoires avec tous les détails (utilise la vue)
SELECT
    source || ' → ' || target as route,
    source_city || ' → ' || target_city as cities,
    airline_name,
    departure_ts,
    arrival_ts,
    duration,
    distance as distance_miles,
    delay as delay_minutes
FROM flights_detailed
ORDER BY RANDOM()
LIMIT 10;

-- Statistiques par route
SELECT
    source,
    target,
    COUNT(*) as flights_count,
    AVG(delay) as avg_delay,
    AVG(EXTRACT(EPOCH FROM (arrival_ts - departure_ts)) / 3600) as avg_duration_hours
FROM flights
GROUP BY source, target
HAVING COUNT(*) >= 5  -- Au moins 5 vols sur cette route
ORDER BY flights_count DESC
LIMIT 20;
