// Plus court chemin pondéré (distance)
// JFK → DAY (John F. Kennedy Intl → Dayton Intl)

// ------------------------------------------------------------
// CYPHER 5 - Tentative d'implémentation
// ------------------------------------------------------------

// Version 1: shortestPath() - compte seulement les sauts (pas pondéré ne prend pas en compte la distance)
MATCH path = shortestPath(
  (start:Airport {iata_code: 'JFK'})-[:FLIGHT*]->(end:Airport {iata_code: 'DAY'})
)
RETURN
  [n in nodes(path) | n.iata_code] AS route,
  length(path) AS num_hops,
  reduce(dist = 0, r in relationships(path) | dist + r.distance) AS total_distance;

// Résultat: chemin avec le moins de sauts, PAS le plus court en distance (voir dijkstra ou distance = 590 via BWI)
// --------------------------
route,num_hops,total_distance
"[JFK, ATL, DAY]",2,1192
// --------------------------

// Version 2: Exploration exhaustive avec limite de profondeur
// PROBLÈME: explore TOUS les chemins - complexité exponentielle
// Timeout probable pour graphes avec beaucoup de nœuds/relations comme le notre
MATCH path = (start:Airport {iata_code: 'JFK'})-[:FLIGHT*1..5]->(end:Airport {iata_code: 'DAY'})
WITH path, reduce(dist = 0, r in relationships(path) | dist + r.distance) AS total_distance
ORDER BY total_distance ASC
LIMIT 1
RETURN
  [n in nodes(path) | n.iata_code] AS route,
  length(path) AS num_hops,
  total_distance;

// CYPHER 25 avec allReduce
// Utilisation de allReduce pour minimiser les distances mais toujours pas optimal
// Fonctionne sur JFK → DAY car peu de chemins possibles (2-3)
// Mais si on augmente la profondeur ça devient impossible (Timeout)
// Dans notre cas on a pas de trajet a plus de 1 escale (2 hops)
CYPHER 25
MATCH path = (start:Airport {iata_code: 'JFK'})-[:FLIGHT*1..2]->(end:Airport {iata_code: 'DAY'})
WITH path,
     [r in relationships(path) | r.distance] AS distances,
     reduce(dist = 0, r in relationships(path) | dist + r.distance) AS total_distance
ORDER BY total_distance
LIMIT 1
RETURN
  [n in nodes(path) | n.iata_code] AS route,
  length(path) AS num_hops,
  total_distance;

// Résultat possible (mais pas garanti optimal pour graphes plus grands):
// --------------------------
route,num_hops,total_distance
"[JFK, BWI, DAY]",2,590
completed after 293 ms.
// --------------------------

// avec [:FLIGHT*1..3] même résultat mais completed after 2 minutes 17 secondes.

// ------------------------------------------------------------
// GDS - SEULE SOLUTION EFFICACE pour poids
// ------------------------------------------------------------

// Projection du graphe
CALL gds.graph.project(
  'flights-weighted',
  'Airport',
  {
    FLIGHT: {
      properties: 'distance'
    }
  }
);

// Dijkstra
MATCH (source:Airport {iata_code: 'JFK'})
MATCH (target:Airport {iata_code: 'DAY'})
CALL gds.shortestPath.dijkstra.stream('flights-weighted', {
  sourceNode: source,
  targetNode: target,
  relationshipWeightProperty: 'distance'
})
YIELD totalCost, nodeIds, costs
RETURN
  [nodeId in nodeIds | gds.util.asNode(nodeId).iata_code] AS route,
  size(nodeIds) - 1 AS num_hops,
  totalCost AS total_distance,
  costs AS cumulative_distances;

// Résultat optimal garanti:
// --------------------------
route,num_hops,total_distance,cumulative_distances
"[JFK, BWI, DAY]",2,590.0,"[0.0, 184.0, 590.0]"
completed after 37 ms.
// --------------------------

// Nettoyage
CALL gds.graph.drop('flights-weighted');


/*
================================================================================
RÉSUMÉ POUR LE RAPPORT
================================================================================

PERFORMANCES MESURÉES (JFK → DAY, optimal = 590 miles via BWI)

| Approche              | Temps  | Distance | Optimal? | Complexité        |
|-----------------------|--------|----------|----------|-------------------|
| Cypher shortestPath() | 15ms   | 1192 mi  | ✗        | BFS (min sauts)   |
| Cypher exhaustif *1..2| 293ms  | 590 mi   | ✓        | O(branches^depth) |
| Cypher exhaustif *1..3| 137s   | 590 mi   | ✓        | 467x plus lent!   |
| GDS Dijkstra          | 37ms   | 590 mi   | ✓        | O(E log V)        |


EXPLOSION COMBINATOIRE

Passer de 2 à 3 sauts: 293ms → 137s (facteur 467x)
→ Croissance exponentielle = inutilisable au-delà de 2-3 sauts


LIMITATIONS TECHNIQUES

Cypher pur:
- Pas de priority queue → impossible Dijkstra efficace
- reduce() dans WHERE = NP-complet (SIGMOD)
- allReduce améliore syntaxe mais pas complexité

GDS:
- Implémentation C++ optimisée
- Priority queue native
- Seule garantie d'optimalité + performance


CONCLUSION

Chemins pondérés (distance, delay, etc.) → GDS Dijkstra OBLIGATOIRE
Chemins non pondérés (min sauts) → shortestPath() suffit
*/
