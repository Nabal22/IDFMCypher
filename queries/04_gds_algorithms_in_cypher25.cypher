// ========================================
// REQUÊTE 4 : IMPLÉMENTATION D'ALGORITHMES GDS EN CYPHER 25
// ========================================
// Objectif : Implémenter directement en Cypher 25 des algorithmes
// normalement disponibles uniquement dans GDS
// Comparaison : Cypher 25 pur vs GDS library

// Projection ORIENTÉE pour Degree Centrality
CALL gds.graph.project(
  'flights-network-directed',
  'Airport',
  'FLIGHT',
  {
    relationshipProperties: ['distance', 'delay']
  }
);

// Projection NON-ORIENTÉE pour Triangle Count
// (triangleCount requiert UNDIRECTED)
CALL gds.graph.project(
  'flights-network-undirected',
  'Airport',
  {
    FLIGHT: {
      orientation: 'UNDIRECTED',
      properties: ['distance', 'delay']
    }
  }
);

// ========================================
// ALGORITHME 1 : Degree Centrality
// ========================================

// 1a. Degree Centrality avec GDS
CALL gds.degree.stream('flights-network-directed')
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

// 2a. Triangle Count avec GDS (utilise la projection UNDIRECTED)
CALL gds.triangleCount.stream('flights-network-undirected')
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
// CLEANUP : Supprimer les projections (optionnel)
// ========================================

// CALL gds.graph.drop('flights-network-directed', false);
// CALL gds.graph.drop('flights-network-undirected', false);
