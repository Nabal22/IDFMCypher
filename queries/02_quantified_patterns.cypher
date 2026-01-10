// Pattern 2: Quantified Graph Patterns
// Objectif: Démontrer l'expressivité des quantified patterns de Cypher 25
// Cas d'usage: Trouver les arrêts avec plusieurs lignes accessibles PMR

// ============================================================================
// CYPHER 25 - QUANTIFIED GRAPH PATTERNS (syntaxe moderne)
// ============================================================================
// ATTENTION: Cypher 25 n'est pas encore disponible dans Neo4j Desktop 5.x
// À tester quand disponible

/*
-- Arrêts avec au moins 3 lignes accessibles PMR
MATCH (s:Stop)
WHERE EXISTS {
  MATCH (s)-[:STOP_TIME]->(:Trip {wheelchair_accessible: 1})-[:BELONGS_TO]->(r:Route)
} >= 3
RETURN
  s.stop_name as stop,
  s.stop_id,
  count(DISTINCT r) as accessible_routes
ORDER BY accessible_routes DESC;

-- Arrêts avec au moins 2 correspondances rapides (<2 min)
MATCH (s:Stop)
WHERE EXISTS {
  MATCH (s)-[t:TRANSFER]->(dest:Stop)
  WHERE t.min_transfer_time < 120
} >= 2
RETURN
  s.stop_name as hub,
  count(*) as fast_transfers
ORDER BY fast_transfers DESC;
*/

// ============================================================================
// CYPHER 5 - VERSION SANS QUANTIFIED PATTERNS (plus verbeuse)
// ============================================================================

// Arrêts avec au moins 3 lignes accessibles PMR
MATCH (s:Stop)-[:STOP_TIME]->(t:Trip {wheelchair_accessible: 1})-[:BELONGS_TO]->(r:Route)
WITH s, count(DISTINCT r) as accessible_routes
WHERE accessible_routes >= 3
RETURN
  s.stop_name as stop,
  s.stop_id,
  accessible_routes
ORDER BY accessible_routes DESC
LIMIT 20;

// Arrêts avec au moins 2 correspondances rapides
MATCH (s:Stop)-[t:TRANSFER]->(dest:Stop)
WHERE t.min_transfer_time < 120 AND t.min_transfer_time IS NOT NULL
WITH s, count(dest) as fast_transfers
WHERE fast_transfers >= 2
RETURN
  s.stop_name as hub,
  s.stop_id,
  fast_transfers
ORDER BY fast_transfers DESC
LIMIT 20;

// ============================================================================
// CAS D'USAGE COMPLEXE: Hubs de correspondance
// ============================================================================
// Arrêts qui sont à la fois:
// - Desservis par plusieurs lignes de métro
// - Avec des correspondances rapides
// - Et accessibles PMR

MATCH (s:Stop)-[:STOP_TIME]->(t:Trip)-[:BELONGS_TO]->(r:Route {route_type: 1})
WITH s, count(DISTINCT r) as metro_lines
WHERE metro_lines >= 2

MATCH (s)-[t:TRANSFER]->(dest:Stop)
WHERE t.min_transfer_time < 180 AND t.min_transfer_time IS NOT NULL
WITH s, metro_lines, count(dest) as transfer_count

MATCH (s)-[:STOP_TIME]->(trip:Trip {wheelchair_accessible: 1})
WITH s, metro_lines, transfer_count, count(trip) as accessible_trips
WHERE accessible_trips > 0

RETURN
  s.stop_name as hub,
  metro_lines,
  transfer_count as fast_transfers,
  accessible_trips
ORDER BY metro_lines DESC, transfer_count DESC
LIMIT 10;

// ============================================================================
// COMPARAISON: Avec vs Sans quantified patterns
// ============================================================================

// Version Cypher 5 (avec sous-requêtes COUNT)
MATCH (s:Stop)
WHERE size((s)-[:STOP_TIME]->(:Trip {wheelchair_accessible: 1})-[:BELONGS_TO]->(:Route)) >= 3
RETURN
  s.stop_name as stop,
  size((s)-[:STOP_TIME]->(:Trip {wheelchair_accessible: 1})-[:BELONGS_TO]->(:Route)) as count
ORDER BY count DESC
LIMIT 10;

// Version Cypher 5 (avec agrégation)
MATCH (s:Stop)-[:STOP_TIME]->(t:Trip {wheelchair_accessible: 1})-[:BELONGS_TO]->(r:Route)
WITH s, count(DISTINCT r) as route_count
WHERE route_count >= 3
RETURN s.stop_name as stop, route_count
ORDER BY route_count DESC
LIMIT 10;

// ============================================================================
// PATTERN AVANCÉ: Détection de hubs multi-modaux
// ============================================================================
// Arrêts connectant plusieurs types de transport

MATCH (s:Stop)
OPTIONAL MATCH (s)-[:STOP_TIME]->(:Trip)-[:BELONGS_TO]->(r_metro:Route {route_type: 1})
OPTIONAL MATCH (s)-[:STOP_TIME]->(:Trip)-[:BELONGS_TO]->(r_bus:Route {route_type: 3})
OPTIONAL MATCH (s)-[:STOP_TIME]->(:Trip)-[:BELONGS_TO]->(r_train:Route {route_type: 2})

WITH s,
  count(DISTINCT r_metro) as metros,
  count(DISTINCT r_bus) as buses,
  count(DISTINCT r_train) as trains,
  (count(DISTINCT r_metro) > 0) as has_metro,
  (count(DISTINCT r_bus) > 0) as has_bus,
  (count(DISTINCT r_train) > 0) as has_train

WHERE (CASE WHEN has_metro THEN 1 ELSE 0 END +
       CASE WHEN has_bus THEN 1 ELSE 0 END +
       CASE WHEN has_train THEN 1 ELSE 0 END) >= 2

RETURN
  s.stop_name as multimodal_hub,
  metros,
  buses,
  trains
ORDER BY metros DESC, buses DESC, trains DESC
LIMIT 15;

// ============================================================================
// ANALYSE AVEC PROFILE
// ============================================================================

PROFILE
MATCH (s:Stop)-[:STOP_TIME]->(t:Trip {wheelchair_accessible: 1})-[:BELONGS_TO]->(r:Route)
WITH s, count(DISTINCT r) as accessible_routes
WHERE accessible_routes >= 3
RETURN
  s.stop_name as stop,
  accessible_routes
ORDER BY accessible_routes DESC
LIMIT 10;

// Questions pour le rapport:
// 1. Différence de performance entre size() et WITH count()?
// 2. Impact du filtrage WHERE dans le MATCH vs après WITH?
// 3. Combien de db hits pour chaque approche?
// 4. Quelle version serait la plus claire avec quantified patterns?
