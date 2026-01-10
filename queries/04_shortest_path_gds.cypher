// Pattern 3B: Shortest Path avec GDS (Graph Data Science)
// Objectif: Utiliser Neo4j GDS pour les algorithmes de graphe optimisés
// Comparaison avec les approches Cypher natives

// ============================================================================
// ÉTAPE 1: Créer une projection de graphe pour GDS
// ============================================================================

// Projeter uniquement les arrêts et les correspondances
CALL gds.graph.project(
  'transport-network',           // Nom de la projection
  'Stop',                        // Label des nœuds
  {
    TRANSFER: {                  // Type de relation
      orientation: 'UNDIRECTED', // Bidirectionnel
      properties: 'min_transfer_time' // Propriété de pondération
    }
  }
)
YIELD graphName, nodeCount, relationshipCount, projectMillis
RETURN graphName, nodeCount, relationshipCount, projectMillis;

// Vérifier la projection
CALL gds.graph.list()
YIELD graphName, nodeCount, relationshipCount
RETURN graphName, nodeCount, relationshipCount;

// ============================================================================
// ÉTAPE 2: Dijkstra - Plus court chemin pondéré
// ============================================================================

// Trouver le plus court chemin entre deux arrêts spécifiques
MATCH (source:Stop), (target:Stop)
WHERE source.stop_name CONTAINS 'Châtelet'
  AND target.stop_name CONTAINS 'Gare'
  AND source.stop_id < target.stop_id
WITH source, target LIMIT 1

CALL gds.shortestPath.dijkstra.stream('transport-network', {
  sourceNode: source,
  targetNode: target,
  relationshipWeightProperty: 'min_transfer_time'
})
YIELD index, sourceNode, targetNode, totalCost, nodeIds, costs, path
RETURN
  gds.util.asNode(sourceNode).stop_name as from_stop,
  gds.util.asNode(targetNode).stop_name as to_stop,
  totalCost as total_seconds,
  [nodeId IN nodeIds | gds.util.asNode(nodeId).stop_name] as path_stops,
  size(nodeIds) - 1 as hops,
  costs;

// ============================================================================
// ÉTAPE 3: A* - Plus court chemin avec heuristique
// ============================================================================

// A* utilise les coordonnées géographiques comme heuristique
MATCH (source:Stop), (target:Stop)
WHERE source.stop_name CONTAINS 'Châtelet'
  AND target.stop_name CONTAINS 'Gare'
  AND source.stop_id < target.stop_id
WITH source, target LIMIT 1

CALL gds.shortestPath.astar.stream('transport-network', {
  sourceNode: source,
  targetNode: target,
  latitudeProperty: 'stop_lat',
  longitudeProperty: 'stop_lon',
  relationshipWeightProperty: 'min_transfer_time'
})
YIELD index, sourceNode, targetNode, totalCost, nodeIds, costs, path
RETURN
  gds.util.asNode(sourceNode).stop_name as from_stop,
  gds.util.asNode(targetNode).stop_name as to_stop,
  totalCost as total_seconds,
  [nodeId IN nodeIds | gds.util.asNode(nodeId).stop_name] as path_stops,
  size(nodeIds) - 1 as hops;

// ============================================================================
// ÉTAPE 4: Yen's K-Shortest Paths - Top K chemins
// ============================================================================

// Trouver les 3 plus courts chemins entre deux arrêts
MATCH (source:Stop), (target:Stop)
WHERE source.stop_name CONTAINS 'Châtelet'
  AND target.stop_name CONTAINS 'Gare'
  AND source.stop_id < target.stop_id
WITH source, target LIMIT 1

CALL gds.shortestPath.yens.stream('transport-network', {
  sourceNode: source,
  targetNode: target,
  k: 3,
  relationshipWeightProperty: 'min_transfer_time'
})
YIELD index, sourceNode, targetNode, totalCost, nodeIds, costs, path
RETURN
  index as path_rank,
  gds.util.asNode(sourceNode).stop_name as from_stop,
  gds.util.asNode(targetNode).stop_name as to_stop,
  totalCost as total_seconds,
  [nodeId IN nodeIds | gds.util.asNode(nodeId).stop_name] as path_stops,
  size(nodeIds) - 1 as hops
ORDER BY index;

// ============================================================================
// ÉTAPE 5: All Pairs Shortest Path - Tous les plus courts chemins
// ============================================================================
// ATTENTION: Peut être très gourmand en mémoire sur de gros graphes

// Calculer les plus courts chemins entre tous les arrêts (limité)
CALL gds.allShortestPaths.dijkstra.stream('transport-network', {
  relationshipWeightProperty: 'min_transfer_time'
})
YIELD sourceNode, targetNode, totalCost, nodeIds
WHERE sourceNode < targetNode  // Éviter les doublons
RETURN
  gds.util.asNode(sourceNode).stop_name as from_stop,
  gds.util.asNode(targetNode).stop_name as to_stop,
  totalCost as total_seconds,
  size(nodeIds) - 1 as hops
ORDER BY totalCost ASC
LIMIT 20;

// ============================================================================
// ÉTAPE 6: Delta-Stepping - Plus court chemin parallèle
// ============================================================================

// Delta-Stepping est optimisé pour les graphes avec beaucoup de nœuds
MATCH (source:Stop), (target:Stop)
WHERE source.stop_name CONTAINS 'Châtelet'
  AND target.stop_name CONTAINS 'Gare'
  AND source.stop_id < target.stop_id
WITH source, target LIMIT 1

CALL gds.shortestPath.deltaStepping.stream('transport-network', {
  sourceNode: source,
  targetNode: target,
  relationshipWeightProperty: 'min_transfer_time',
  delta: 2.0
})
YIELD index, sourceNode, targetNode, totalCost, nodeIds, costs, path
RETURN
  gds.util.asNode(sourceNode).stop_name as from_stop,
  gds.util.asNode(targetNode).stop_name as to_stop,
  totalCost as total_seconds,
  size(nodeIds) - 1 as hops;

// ============================================================================
// COMPARAISON: Dijkstra vs A* vs Delta-Stepping
// ============================================================================

// Mesurer le temps d'exécution de chaque algorithme
MATCH (source:Stop), (target:Stop)
WHERE source.stop_name CONTAINS 'Châtelet'
  AND target.stop_name CONTAINS 'Gare'
  AND source.stop_id < target.stop_id
WITH source, target LIMIT 1

// Dijkstra
CALL gds.shortestPath.dijkstra.stats('transport-network', {
  sourceNode: source,
  targetNode: target,
  relationshipWeightProperty: 'min_transfer_time'
})
YIELD computeMillis
RETURN 'Dijkstra' as algorithm, computeMillis;

// A*
// Note: A* nécessite les coordonnées géographiques

// ============================================================================
// NETTOYAGE: Supprimer la projection
// ============================================================================

// Lister toutes les projections
CALL gds.graph.list()
YIELD graphName
RETURN graphName;

// Supprimer la projection 'transport-network'
CALL gds.graph.drop('transport-network')
YIELD graphName, nodeCount, relationshipCount;

// ============================================================================
// PROJECTION ALTERNATIVE: Inclure STOP_TIME et PATHWAY
// ============================================================================

// Créer une projection multi-relations
CALL gds.graph.project(
  'transport-network-full',
  'Stop',
  {
    TRANSFER: {
      properties: 'min_transfer_time'
    },
    PATHWAY: {
      properties: 'traversal_time'
    }
  }
)
YIELD graphName, nodeCount, relationshipCount;

// Utiliser cette projection pour Dijkstra
MATCH (source:Stop), (target:Stop)
WHERE source.stop_name CONTAINS 'Châtelet'
  AND target.stop_name CONTAINS 'Gare'
  AND source.stop_id < target.stop_id
WITH source, target LIMIT 1

CALL gds.shortestPath.dijkstra.stream('transport-network-full', {
  sourceNode: source,
  targetNode: target,
  relationshipWeightProperty: 'min_transfer_time'
})
YIELD totalCost, nodeIds
RETURN
  totalCost,
  [nodeId IN nodeIds | gds.util.asNode(nodeId).stop_name] as path;

// Nettoyage
CALL gds.graph.drop('transport-network-full');

// ============================================================================
// QUESTIONS POUR LE RAPPORT
// ============================================================================
// 1. Performance Dijkstra GDS vs shortestPath Cypher 5?
// 2. Quand utiliser A* vs Dijkstra?
// 3. Impact de la projection sur les performances?
// 4. Yen's K-Shortest vs allShortestPaths de Cypher?
// 5. Mémoire utilisée par All Pairs Shortest Path?
