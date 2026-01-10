// Pattern 1: Increasing Property Paths (Departure Times)
// Objectif: Trouver des chemins où les horaires de départ augmentent strictement
// Comparaison: Cypher 5 (problématique) vs Cypher 25 (allReduce) vs SQL (recursive)

// ============================================================================
// CYPHER 5 - VERSION PROBLÉMATIQUE (reduce dans WHERE)
// ============================================================================
// ATTENTION: Cette requête peut timeout sur des trajets longs (>10 stops)
// Complexité exponentielle cachée par la syntaxe simple

// Recherche de trajets avec horaires croissants sur une ligne spécifique
MATCH (r:Route {route_short_name: '3'})
MATCH path = (start:Stop)-[:STOP_TIME*2..5]->(t:Trip)-[:BELONGS_TO]->(r)
WHERE ALL(i IN range(0, size(relationships(path))-2) WHERE
  relationships(path)[i].departure_time < relationships(path)[i+1].departure_time
)
RETURN
  [n IN nodes(path) WHERE n:Stop | n.stop_name] as stops,
  [r IN relationships(path) WHERE type(r) = 'STOP_TIME' | r.departure_time] as times,
  length(path) as hops
LIMIT 10;

// ============================================================================
// CYPHER 25 - VERSION OPTIMISÉE (allReduce)
// ============================================================================
// ATTENTION: Cypher 25 n'est pas encore disponible dans Neo4j Desktop 5.x
// Cette syntaxe est documentée mais non implémentée à ce jour
// À tester quand Cypher 25 sera disponible

/*
MATCH (r:Route {route_short_name: '3'})
MATCH path = (start:Stop)-[:STOP_TIME*2..5]->(t:Trip)-[:BELONGS_TO]->(r)
WHERE allReduce(
  rel IN relationships(path) WHERE type(rel) = 'STOP_TIME' |
  rel.departure_time,
  prev, curr | prev < curr
)
RETURN
  [n IN nodes(path) WHERE n:Stop | n.stop_name] as stops,
  [r IN relationships(path) WHERE type(r) = 'STOP_TIME' | r.departure_time] as times,
  length(path) as hops
LIMIT 10;
*/

// ============================================================================
// CYPHER 5 - VERSION ALTERNATIVE (déplacer le filtre hors WHERE)
// ============================================================================
// Approche: calculer d'abord, filtrer ensuite (évite reduce dans WHERE)

MATCH (r:Route {route_short_name: '3'})
MATCH path = (start:Stop)-[:STOP_TIME*2..5]->(t:Trip)-[:BELONGS_TO]->(r)
WITH path, relationships(path) as rels
WITH path, rels,
  ALL(i IN range(0, size(rels)-2) WHERE
    rels[i].departure_time < rels[i+1].departure_time
  ) as is_increasing
WHERE is_increasing = true
RETURN
  [n IN nodes(path) WHERE n:Stop | n.stop_name] as stops,
  [r IN rels WHERE type(r) = 'STOP_TIME' | r.departure_time] as times,
  length(path) as hops
LIMIT 10;

// ============================================================================
// TEST DE PERFORMANCE: Version simplifiée pour mesurer le timeout threshold
// ============================================================================
// Objectif: Déterminer à partir de combien de stops la requête timeout

// Test avec 2 stops
MATCH (r:Route {route_short_name: '3'})
MATCH path = (start:Stop)-[:STOP_TIME*2]->(t:Trip)-[:BELONGS_TO]->(r)
WHERE ALL(i IN range(0, size(relationships(path))-2) WHERE
  relationships(path)[i].departure_time < relationships(path)[i+1].departure_time
)
RETURN count(path) as path_count;

// Test avec 3 stops
MATCH (r:Route {route_short_name: '3'})
MATCH path = (start:Stop)-[:STOP_TIME*3]->(t:Trip)-[:BELONGS_TO]->(r)
WHERE ALL(i IN range(0, size(relationships(path))-2) WHERE
  relationships(path)[i].departure_time < relationships(path)[i+1].departure_time
)
RETURN count(path) as path_count;

// Test avec 5 stops
MATCH (r:Route {route_short_name: '3'})
MATCH path = (start:Stop)-[:STOP_TIME*5]->(t:Trip)-[:BELONGS_TO]->(r)
WHERE ALL(i IN range(0, size(relationships(path))-2) WHERE
  relationships(path)[i].departure_time < relationships(path)[i+1].departure_time
)
RETURN count(path) as path_count;

// ============================================================================
// ANALYSE AVEC PROFILE
// ============================================================================
// À exécuter pour obtenir le plan d'exécution

PROFILE
MATCH (r:Route {route_short_name: '3'})
MATCH path = (start:Stop)-[:STOP_TIME*2..3]->(t:Trip)-[:BELONGS_TO]->(r)
WHERE ALL(i IN range(0, size(relationships(path))-2) WHERE
  relationships(path)[i].departure_time < relationships(path)[i+1].departure_time
)
RETURN count(path) as path_count;

// Questions pour le rapport:
// 1. À partir de combien de stops la requête Cypher 5 timeout?
// 2. Quel est l'algorithme utilisé (Expand All, BFS, etc.)?
// 3. Combien de db hits sont nécessaires?
// 4. La version "alternative" est-elle plus rapide?
