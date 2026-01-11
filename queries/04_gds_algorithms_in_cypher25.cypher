// ========================================
// REQUÊTE 4 : IMPLÉMENTATION D'ALGORITHMES GDS EN CYPHER 25
// ========================================
// Objectif : Implémenter directement en Cypher 25 des algorithmes
// normalement disponibles uniquement dans GDS
// Comparaison : Cypher 25 pur vs GDS library

// ========================================
// SETUP : Créer la projection GDS pour comparaison
// ========================================

// Syntaxe corrigée pour GDS projection (compatible avec votre version)
CALL gds.graph.project(
  'flights-network',
  'Airport',
  'FLIGHT',
  {
    relationshipProperties: ['distance', 'delay']
  }
);

// ========================================
// ALGORITHME 1 : Degree Centrality
// ========================================

// 1a. Degree Centrality avec GDS
CALL gds.degree.stream('flights-network')
YIELD nodeId, score
RETURN
  gds.util.asNode(nodeId).iata_code AS airport,
  gds.util.asNode(nodeId).city AS city,
  score AS degree
ORDER BY degree DESC
LIMIT 10;

// 1b. Degree Centrality en Cypher 25 (facile !)
CYPHER 25
MATCH (a:Airport)
OPTIONAL MATCH (a)-[out:FLIGHT]->()
OPTIONAL MATCH (a)<-[in:FLIGHT]-()
RETURN
  a.iata_code AS airport,
  a.city AS city,
  count(DISTINCT out) AS out_degree,
  count(DISTINCT in) AS in_degree,
  count(DISTINCT out) + count(DISTINCT in) AS total_degree
ORDER BY total_degree DESC
LIMIT 10;

// ========================================
// ALGORITHME 2 : Triangle Count (Clustering Coefficient)
// ========================================

// 2a. Triangle Count avec GDS
CALL gds.triangleCount.stream('flights-network')
YIELD nodeId, triangleCount
WHERE triangleCount > 0
RETURN
  gds.util.asNode(nodeId).iata_code AS airport,
  gds.util.asNode(nodeId).city AS city,
  triangleCount
ORDER BY triangleCount DESC
LIMIT 10;

// 2b. Triangle Count en Cypher 25
CYPHER 25
MATCH (a:Airport)-[:FLIGHT]->(b:Airport)-[:FLIGHT]->(c:Airport)-[:FLIGHT]->(a)
WITH a, count(DISTINCT [b, c]) AS triangles
WHERE triangles > 0
RETURN
  a.iata_code AS airport,
  a.city AS city,
  triangles AS triangle_count
ORDER BY triangle_count DESC
LIMIT 10;

// ========================================
// COMPARAISON DE PERFORMANCE
// ========================================

// Degree Centrality - GDS avec PROFILE
PROFILE
CALL gds.degree.stream('flights-network')
YIELD nodeId, score
RETURN count(*);

// Degree Centrality - Cypher 25 avec PROFILE
CYPHER 25
PROFILE
MATCH (a:Airport)
OPTIONAL MATCH (a)-[out:FLIGHT]->()
OPTIONAL MATCH (a)<-[in:FLIGHT]-()
RETURN count(DISTINCT a);

// ========================================
// ALGORITHME 3 (BONUS) : Betweenness approximatif
// ========================================
// Montre les limites de Cypher 25 pour les algos complexes

// 3a. Betweenness avec GDS
CALL gds.betweenness.stream('flights-network', {samplingSize: 50})
YIELD nodeId, score
RETURN gds.util.asNode(nodeId).iata_code AS airport, score
ORDER BY score DESC
LIMIT 10;

// 3b. Betweenness approximatif en Cypher 25
// Basé sur comptage de passages dans plus courts chemins échantillonnés
CYPHER 25
// Utiliser des aéroports moyens qui nécessitent souvent des connexions
WITH ['BOS', 'MIA', 'SEA', 'SAN', 'PDX', 'SLC', 'MSP', 'DTW', 'PHL', 'CLT',
      'MCO', 'FLL', 'TPA', 'BNA', 'OAK', 'SJC', 'SMF', 'RDU', 'AUS', 'SAT'] AS sample_airports

// Pour chaque paire d'aéroports
UNWIND sample_airports AS start_code
UNWIND sample_airports AS end_code
WITH start_code, end_code
WHERE start_code < end_code

MATCH (start:Airport {iata_code: start_code}), (end:Airport {iata_code: end_code})
// Trouver tous les plus courts chemins (accepte 1-4 hops)
MATCH path = allShortestPaths((start)-[:FLIGHT*1..4]->(end))
// Filtrer pour garder seulement chemins avec au moins 2 hops
WHERE length(path) >= 2

// Compter passages par chaque nœud intermédiaire
WITH path, start, end, nodes(path) AS all_nodes
UNWIND all_nodes AS node
WITH node, start, end
WHERE node <> start AND node <> end  // Exclure les endpoints

RETURN
  node.iata_code AS airport,
  node.city AS city,
  count(*) AS betweenness_score
ORDER BY betweenness_score DESC
LIMIT 10;

// ========================================
// CLEANUP
// ========================================
CALL gds.graph.drop('flights-network');