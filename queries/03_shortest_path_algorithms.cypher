// ========================================
// REQUÊTE 3 : SHORTEST PATH ALGORITHMS
// ========================================
// Comparaison : Cypher 5, Cypher 25, et GDS
// Analyse des algorithmes : BFS unidirectionnel vs bidirectionnel

// ========================================
// CYPHER 5 : shortestPath()
// ========================================

// 1a. Plus court chemin non pondéré (nombre de sauts minimum)
MATCH (start:Airport {iata_code: 'LAX'}), (end:Airport {iata_code: 'JFK'})
MATCH path = shortestPath((start)-[:FLIGHT*]-(end))
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  length(path) AS hops,
  [r IN relationships(path) | {
    airline: r.airline,
    delay: r.delay,
    distance: r.distance
  }] AS flights;

// 1b. Tous les plus courts chemins (si plusieurs avec même longueur)
MATCH (start:Airport {iata_code: 'LAX'}), (end:Airport {iata_code: 'JFK'})
MATCH path = allShortestPaths((start)-[:FLIGHT*]-(end))
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  length(path) AS hops,
  reduce(total_delay = 0.0, r IN relationships(path) | total_delay + r.delay) AS total_delay
ORDER BY total_delay
LIMIT 10;

// 1c. Plus court chemin avec limite de profondeur
MATCH (start:Airport {iata_code: 'LAX'}), (end:Airport {iata_code: 'JFK'})
MATCH path = shortestPath((start)-[:FLIGHT*..5]-(end))
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  length(path) AS hops;

// ATTENTION : Cypher 5 shortestPath() ne supporte PAS les poids sur les arêtes !
// Pour chemins pondérés, il faut utiliser GDS ou variable length avec filtrage

// ========================================
// CYPHER 25 : SHORTEST keyword
// ========================================

// 2a. Plus court chemin avec syntaxe moderne
CYPHER 25
MATCH SHORTEST 1 path = (start:Airport {iata_code: 'LAX'})
  (()-[:FLIGHT]->(:Airport))+
  (end:Airport {iata_code: 'JFK'})
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  length(path) AS hops,
  reduce(dist = 0, r IN relationships(path) | dist + r.distance) AS total_distance;

// 2b. K plus courts chemins (top K)
CYPHER 25
MATCH SHORTEST 5 PATHS path = (start:Airport {iata_code: 'LAX'})
  (()-[:FLIGHT]->(:Airport))+
  (end:Airport {iata_code: 'JFK'})
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  length(path) AS hops,
  reduce(dist = 0, r IN relationships(path) | dist + r.distance) AS total_distance,
  reduce(delay = 0.0, r IN relationships(path) | delay + r.delay) AS total_delay
ORDER BY hops, total_distance;

// 2c. Plus court chemin avec contraintes (correspondances valides)
CYPHER 25
MATCH SHORTEST 1 path = (start:Airport {iata_code: 'LAX'})
  (()-[:FLIGHT]->(:Airport))+
  (end:Airport {iata_code: 'JFK'})
WHERE allReduce(
  prev_arrival = datetime('2015-01-01T00:00:00'),
  rel IN relationships(path) |
    CASE
      WHEN rel.departure_ts >= prev_arrival + duration({minutes: 30})
      THEN rel.arrival_ts
      ELSE null
    END,
  prev_arrival IS NOT NULL
)
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  length(path) AS hops;

// ========================================
// NEO4J GDS : Shortest Path Algorithms
// ========================================

// Setup : Créer une projection du graphe pour GDS

// 3a. Créer la projection native (plus performant)
CALL gds.graph.project(
  'flights-graph',
  'Airport',
  {
    FLIGHT: {
      orientation: 'NATURAL'
    }
  },
  {
    nodeProperties: ['iata_code', 'city'],
    relationshipProperties: ['distance', 'delay']
  }
);

// 3b. Dijkstra : Plus court chemin pondéré par distance
MATCH (start:Airport {iata_code: 'LAX'}), (end:Airport {iata_code: 'JFK'})
CALL gds.shortestPath.dijkstra.stream('flights-graph', {
  sourceNode: start,
  targetNode: end,
  relationshipWeightProperty: 'distance'
})
YIELD index, sourceNode, targetNode, totalCost, nodeIds, costs, path
RETURN
  [nodeId IN nodeIds | gds.util.asNode(nodeId).iata_code] AS route,
  totalCost AS total_distance_miles,
  size(nodeIds) - 1 AS hops;

// 3c. A* : Plus court chemin avec heuristique (distance géographique)
MATCH (start:Airport {iata_code: 'LAX'}), (end:Airport {iata_code: 'JFK'})
CALL gds.shortestPath.astar.stream('flights-graph', {
  sourceNode: start,
  targetNode: end,
  latitudeProperty: 'latitude',
  longitudeProperty: 'longitude',
  relationshipWeightProperty: 'distance'
})
YIELD index, sourceNode, targetNode, totalCost, nodeIds, costs, path
RETURN
  [nodeId IN nodeIds | gds.util.asNode(nodeId).iata_code] AS route,
  totalCost AS total_distance_miles,
  size(nodeIds) - 1 AS hops;

// 3d. Yen's K Shortest Paths : Top K chemins pondérés
MATCH (start:Airport {iata_code: 'LAX'}), (end:Airport {iata_code: 'JFK'})
CALL gds.shortestPath.yens.stream('flights-graph', {
  sourceNode: start,
  targetNode: end,
  k: 5,
  relationshipWeightProperty: 'distance'
})
YIELD index, sourceNode, targetNode, totalCost, nodeIds, costs, path
RETURN
  index AS rank,
  [nodeId IN nodeIds | gds.util.asNode(nodeId).iata_code] AS route,
  totalCost AS total_distance_miles,
  size(nodeIds) - 1 AS hops
ORDER BY rank;

// 3e. Delta-Stepping : Parallèle pour grands graphes
MATCH (start:Airport {iata_code: 'LAX'}), (end:Airport {iata_code: 'JFK'})
CALL gds.allShortestPaths.delta.stream('flights-graph', {
  sourceNode: start,
  relationshipWeightProperty: 'distance',
  delta: 100.0
})
YIELD index, sourceNode, targetNode, totalCost, nodeIds, costs, path
WHERE targetNode = end
RETURN
  [nodeId IN nodeIds | gds.util.asNode(nodeId).iata_code] AS route,
  totalCost AS total_distance_miles,
  size(nodeIds) - 1 AS hops
LIMIT 1;

// ========================================
// COMPARAISON : Différents types de poids
// ========================================

// 4a. Chemin le plus COURT en distance
MATCH (start:Airport {iata_code: 'LAX'}), (end:Airport {iata_code: 'MIA'})
CALL gds.shortestPath.dijkstra.stream('flights-graph', {
  sourceNode: start,
  targetNode: end,
  relationshipWeightProperty: 'distance'
})
YIELD totalCost, nodeIds
RETURN
  'Shortest by distance' AS metric,
  [nodeId IN nodeIds | gds.util.asNode(nodeId).iata_code] AS route,
  totalCost AS total_distance,
  size(nodeIds) - 1 AS hops;

// 4b. Chemin le plus RAPIDE (minimum de retard)
// NOTE : GDS ne peut pas utiliser delay directement car certains sont négatifs
// On doit transformer : weight = delay + offset pour avoir tous positifs

// Alternative : Calculer manuellement avec allShortestPaths + reduce
MATCH (start:Airport {iata_code: 'LAX'}), (end:Airport {iata_code: 'MIA'})
MATCH paths = allShortestPaths((start)-[:FLIGHT*]-(end))
WITH paths, reduce(total = 0.0, r IN relationships(paths) | total + r.delay) AS total_delay
ORDER BY total_delay
LIMIT 1
RETURN
  'Minimum delay' AS metric,
  [n IN nodes(paths) | n.iata_code] AS route,
  total_delay AS total_delay_minutes,
  length(paths) AS hops;

// ========================================
// ANALYSE : BFS Unidirectionnel vs Bidirectionnel
// ========================================

// 5a. Forcer BFS unidirectionnel (variable length avec limite)
PROFILE
MATCH (start:Airport {iata_code: 'LAX'}), (end:Airport {iata_code: 'JFK'})
MATCH path = (start)-[:FLIGHT*1..10]->(end)
WITH path
ORDER BY length(path)
LIMIT 1
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  length(path) AS hops;

// 5b. shortestPath (utilise BFS bidirectionnel optimisé)
PROFILE
MATCH (start:Airport {iata_code: 'LAX'}), (end:Airport {iata_code: 'JFK'})
MATCH path = shortestPath((start)-[:FLIGHT*]-(end))
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  length(path) AS hops;

// Dans le PROFILE, regarder :
// - db hits : bidirectionnel devrait avoir moins de hits
// - Algorithm : "BidirectionalShortestPath" vs "VarLengthExpand"

// ========================================
// BENCHMARKS : Performance Comparison
// ========================================

// Mesurer temps d'exécution pour différents algorithmes

// Benchmark 1 : Cypher 5 shortestPath
:param start => 'LAX';
:param end => 'JFK';

PROFILE
MATCH (s:Airport {iata_code: $start}), (e:Airport {iata_code: $end})
MATCH path = shortestPath((s)-[:FLIGHT*]-(e))
RETURN length(path) AS hops;

// Benchmark 2 : Cypher 25 SHORTEST
CYPHER 25
PROFILE
MATCH SHORTEST 1 path = (s:Airport {iata_code: $start})
  (()-[:FLIGHT]->(:Airport))+
  (e:Airport {iata_code: $end})
RETURN length(path) AS hops;

// Benchmark 3 : GDS Dijkstra
PROFILE
MATCH (s:Airport {iata_code: $start}), (e:Airport {iata_code: $end})
CALL gds.shortestPath.dijkstra.stream('flights-graph', {
  sourceNode: s,
  targetNode: e,
  relationshipWeightProperty: 'distance'
})
YIELD totalCost, nodeIds
RETURN size(nodeIds) - 1 AS hops;

// ========================================
// CLEANUP : Supprimer la projection GDS
// ========================================

CALL gds.graph.drop('flights-graph');

// ========================================
// POINTS CLÉS POUR LE RAPPORT
// ========================================

/*
1. CYPHER 5 shortestPath() :

   AVANTAGES :
   - Simple, une ligne
   - BFS bidirectionnel optimisé
   - Bonne performance sur chemins non pondérés

   LIMITATIONS :
   - PAS de support pour poids sur arêtes
   - Pas de top-K (seulement allShortestPaths pour même longueur)
   - Relations non orientées par défaut

2. CYPHER 25 SHORTEST :

   AVANTAGES :
   - Syntaxe moderne, plus claire
   - Support top-K : SHORTEST k PATHS
   - Peut combiner avec allReduce pour contraintes

   LIMITATIONS :
   - Toujours non pondéré (par rapport à une propriété)
   - Doit utiliser GDS pour Dijkstra/A*

3. NEO4J GDS :

   ALGORITHMES :
   - Dijkstra : Plus court chemin pondéré (distance, temps, etc.)
   - A* : Utilise heuristique géographique (lat/lon)
   - Yen : Top-K chemins pondérés
   - Delta-Stepping : Parallèle pour très grands graphes

   AVANTAGES :
   - Support complet des poids
   - Algorithmes optimisés (C++)
   - Parallélisation
   - Heuristiques (A*)

   LIMITATIONS :
   - Nécessite projection du graphe (overhead)
   - Poids doivent être >= 0
   - API moins intuitive que Cypher

4. BFS UNIDIRECTIONNEL vs BIDIRECTIONNEL :

   Unidirectionnel :
   - Explore depuis source vers target
   - O(b^d) où b=branching factor, d=depth
   - Exemple : si b=10, d=5 → 100,000 nœuds

   Bidirectionnel :
   - Explore depuis source ET target simultanément
   - Se rencontrent au milieu
   - O(2 * b^(d/2)) → si b=10, d=5 → 2*316 = 632 nœuds
   - **Speedup : ~158x** dans cet exemple !

   Dans Neo4j :
   - shortestPath() utilise BFS bidirectionnel
   - Variable length -[:FLIGHT*]-> est unidirectionnel

5. RÉSULTATS ATTENDUS (PROFILE) :

   Cypher 5 shortestPath :
   - db hits : ~1,000-5,000 (bidirectionnel)
   - Temps : <50ms

   Variable length unidirectionnel :
   - db hits : ~50,000-100,000
   - Temps : 500ms-2s

   GDS Dijkstra :
   - db hits : ~500-1,000 (projection déjà en mémoire)
   - Temps : <20ms (après projection)
   - Projection : ~1-2s (une seule fois)

6. POUR LE RAPPORT :

   a) Montrer les 3 approches côte à côte
   b) Comparer les PROFILE (db hits, temps)
   c) Expliquer BFS bidirectionnel (diagram)
   d) Montrer quand utiliser quoi :
      - Non pondéré, simple : Cypher 5 shortestPath
      - Non pondéré, contraintes : Cypher 25 SHORTEST + allReduce
      - Pondéré, performance : GDS Dijkstra/A*/Yen
   e) Référencer les algorithmes dans le plan d'exécution
   f) Calculer speedup bidirectionnel vs unidirectionnel
*/
