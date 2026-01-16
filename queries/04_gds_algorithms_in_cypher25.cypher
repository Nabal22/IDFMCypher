// REQUÊTE 4 : IMPLÉMENTATION D'ALGORITHMES GDS EN CYPHER 25
// Comparaison : Cypher 25 pur vs GDS library

// Projection
CALL gds.graph.project(
  'flights-network-directed',
  'Airport',
  'FLIGHT',
  {
    relationshipProperties: ['distance', 'delay']
  }
);

// Degree Centrality

// Degree Centrality avec GDS
CALL gds.degree.stream('flights-network-directed')
YIELD nodeId, score
RETURN
  gds.util.asNode(nodeId).iata_code AS airport,
  gds.util.asNode(nodeId).city AS city,
  score AS degree
ORDER BY degree DESC
LIMIT 10;
// Completed after 30 ms

// Degree Centrality en Cypher 25
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
// Completed after 43 154 ms

CALL gds.graph.drop('flights-network-directed', false);
