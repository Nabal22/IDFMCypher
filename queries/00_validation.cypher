// ========================================
// Requêtes de Validation Post-Import
// ========================================

// 1. STATISTIQUES GÉNÉRALES
// ========================================

// Compter tous les types de nœuds
MATCH (a:Airport) RETURN 'Airports' as type, count(a) as count
UNION
MATCH (al:Airline) RETURN 'Airlines' as type, count(al) as count;

// Compter les relations
MATCH ()-[f:FLIGHT]->()
RETURN count(f) as total_flights;

// Vue d'ensemble du schéma
CALL db.schema.visualization();


// 2. VÉRIFICATIONS DE QUALITÉ DES DONNÉES
// ========================================

// Vérifier qu'il n'y a pas de vols vers le même aéroport
MATCH (a:Airport)-[f:FLIGHT]->(a)
RETURN count(f) as self_loops;
// Résultat attendu: 0

// Vérifier qu'il n'y a pas de valeurs nulles dans les timestamps
MATCH ()-[f:FLIGHT]->()
WHERE f.departure_ts IS NULL OR f.arrival_ts IS NULL
RETURN count(f) as null_timestamps;
// Résultat attendu: 0

// Vérifier la distribution des retards
MATCH ()-[f:FLIGHT]->()
RETURN
  min(f.delay) as min_delay,
  max(f.delay) as max_delay,
  avg(f.delay) as avg_delay,
  percentileCont(f.delay, 0.5) as median_delay;


// 3. ANALYSE DU RÉSEAU
// ========================================

// Top 10 des aéroports par nombre de départs
MATCH (a:Airport)-[f:FLIGHT]->()
RETURN
  a.iata_code as airport,
  a.city as city,
  count(f) as departures
ORDER BY departures DESC
LIMIT 10;

// Top 10 des aéroports par nombre d'arrivées
MATCH (a:Airport)<-[f:FLIGHT]-()
RETURN
  a.iata_code as airport,
  a.city as city,
  count(f) as arrivals
ORDER BY arrivals DESC
LIMIT 10;

// Distribution des compagnies
MATCH ()-[f:FLIGHT]->()
RETURN
  f.airline as airline,
  f.airline_name as name,
  count(f) as flights
ORDER BY flights DESC;


// 4. ANALYSE TEMPORELLE
// ========================================

// Distribution des vols par jour
MATCH ()-[f:FLIGHT]->()
RETURN
  f.departure_ts.day as day,
  count(f) as flights
ORDER BY day;

// Heures de pointe (par heure de départ)
MATCH ()-[f:FLIGHT]->()
RETURN
  f.departure_ts.hour as hour,
  count(f) as flights
ORDER BY hour;

// Vols les plus longs (par durée)
MATCH (source)-[f:FLIGHT]->(target)
RETURN
  source.iata_code as from,
  target.iata_code as to,
  source.city as from_city,
  target.city as to_city,
  f.airline as airline,
  f.departure_ts as departure,
  f.arrival_ts as arrival,
  duration.inSeconds(f.departure_ts, f.arrival_ts) / 3600.0 as duration_hours
ORDER BY duration_hours DESC
LIMIT 10;


// 5. ANALYSE GÉOGRAPHIQUE
// ========================================

// Vols les plus longs par distance
MATCH (source)-[f:FLIGHT]->(target)
RETURN
  source.iata_code as from,
  target.iata_code as to,
  source.city as from_city,
  target.city as to_city,
  f.distance as distance_miles
ORDER BY distance_miles DESC
LIMIT 10;

// Aéroports les plus au nord/sud/est/ouest
MATCH (a:Airport)
RETURN a.iata_code, a.city, a.latitude, a.longitude
ORDER BY a.latitude DESC
LIMIT 1
UNION
MATCH (a:Airport)
RETURN a.iata_code, a.city, a.latitude, a.longitude
ORDER BY a.latitude ASC
LIMIT 1
UNION
MATCH (a:Airport)
RETURN a.iata_code, a.city, a.latitude, a.longitude
ORDER BY a.longitude DESC
LIMIT 1
UNION
MATCH (a:Airport)
RETURN a.iata_code, a.city, a.latitude, a.longitude
ORDER BY a.longitude ASC
LIMIT 1;


// 6. ANALYSE DES RETARDS
// ========================================

// Top 10 des vols les plus en retard
MATCH (source)-[f:FLIGHT]->(target)
WHERE f.delay > 0
RETURN
  source.iata_code as from,
  target.iata_code as to,
  f.airline as airline,
  f.departure_ts as scheduled_departure,
  f.delay as delay_minutes
ORDER BY delay_minutes DESC
LIMIT 10;

// Top 10 des vols les plus en avance
MATCH (source)-[f:FLIGHT]->(target)
WHERE f.delay < 0
RETURN
  source.iata_code as from,
  target.iata_code as to,
  f.airline as airline,
  f.departure_ts as scheduled_departure,
  f.delay as early_minutes
ORDER BY early_minutes ASC
LIMIT 10;

// Retard moyen par compagnie
MATCH ()-[f:FLIGHT]->()
RETURN
  f.airline as airline,
  f.airline_name as name,
  count(f) as total_flights,
  avg(f.delay) as avg_delay,
  sum(CASE WHEN f.delay > 0 THEN 1 ELSE 0 END) as delayed_flights,
  100.0 * sum(CASE WHEN f.delay > 0 THEN 1 ELSE 0 END) / count(f) as delay_rate_pct
ORDER BY avg_delay DESC;

// Retard moyen par aéroport de départ
MATCH (a:Airport)-[f:FLIGHT]->()
WITH a, count(f) as flights, avg(f.delay) as avg_delay
WHERE flights >= 100  // Au moins 100 vols
RETURN
  a.iata_code as airport,
  a.city as city,
  flights,
  avg_delay
ORDER BY avg_delay DESC
LIMIT 10;


// 7. CONNECTIVITÉ
// ========================================

// Aéroports isolés (pas de connexion directe)
MATCH (a:Airport)
WHERE NOT (a)-[:FLIGHT]-()
RETURN a.iata_code, a.city;
// Résultat attendu: vide (tous les aéroports devraient être connectés)

// Nombre de destinations directes par aéroport
MATCH (a:Airport)-[:FLIGHT]->(dest:Airport)
WITH a, count(DISTINCT dest) as direct_destinations
RETURN
  a.iata_code as airport,
  a.city as city,
  direct_destinations
ORDER BY direct_destinations DESC
LIMIT 10;

// Routes les plus fréquentées (paires d'aéroports)
MATCH (a1:Airport)-[f:FLIGHT]->(a2:Airport)
WHERE a1.iata_code < a2.iata_code  // Éviter les doublons
WITH a1, a2, count(f) as flights_one_way
MATCH (a2)-[f2:FLIGHT]->(a1)
WITH a1, a2, flights_one_way, count(f2) as flights_return
RETURN
  a1.iata_code as airport1,
  a2.iata_code as airport2,
  a1.city as city1,
  a2.city as city2,
  flights_one_way,
  flights_return,
  flights_one_way + flights_return as total_flights
ORDER BY total_flights DESC
LIMIT 10;


// 8. EXEMPLES DE VOLS
// ========================================

// 10 vols aléatoires avec tous les détails
MATCH (source:Airport)-[f:FLIGHT]->(target:Airport)
RETURN
  source.iata_code + ' → ' + target.iata_code as route,
  source.city + ' → ' + target.city as cities,
  f.airline_name as airline,
  f.departure_ts as departure,
  f.arrival_ts as arrival,
  f.distance as distance_miles,
  f.delay as delay_minutes
ORDER BY rand()
LIMIT 10;
