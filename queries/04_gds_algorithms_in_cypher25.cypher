// ========================================
// REQUÊTE 4 : IMPLÉMENTATION D'ALGORITHMES GDS EN CYPHER 25
// ========================================
// Objectif : Implémenter directement en Cypher 25 des algorithmes
// normalement disponibles uniquement dans GDS
// Comparaison : Cypher 25 pur vs GDS library

// ========================================
// SETUP : Créer la projection GDS pour comparaison
// ========================================

CALL gds.graph.project(
  'flights-network',
  'Airport',
  {
    FLIGHT: {
      orientation: 'NATURAL',
      properties: ['distance', 'delay']
    }
  },
  {
    nodeProperties: ['iata_code', 'city', 'latitude', 'longitude']
  }
);

// ========================================
// ALGORITHME 1 : PageRank (Identifier les Hubs)
// ========================================

// 1a. PageRank avec GDS (référence)
CALL gds.pageRank.stream('flights-network', {
  maxIterations: 20,
  dampingFactor: 0.85
})
YIELD nodeId, score
RETURN
  gds.util.asNode(nodeId).iata_code AS airport,
  gds.util.asNode(nodeId).city AS city,
  score AS pagerank
ORDER BY pagerank DESC
LIMIT 10;

// 1b. PageRank approximatif en Cypher 25
// Utilise itérations avec COLLECT/UNWIND
CYPHER 25
WITH 0.85 AS damping, 20 AS max_iterations

// Initialiser : tous les aéroports avec score 1.0
MATCH (a:Airport)
WITH collect({node: a, score: 1.0}) AS nodes, damping, max_iterations

// Itération 1-20 (simulation)
// Note : Cypher ne supporte pas de vraies boucles, donc on doit dérouler
UNWIND range(1, max_iterations) AS iteration
WITH nodes, damping, iteration

// Calculer nouveau score pour chaque nœud
UNWIND nodes AS n
MATCH (n.node)<-[:FLIGHT]-(incoming)
WITH n, damping, collect(incoming) AS in_nodes, nodes
// Approximation : score = (1-d) + d * sum(score_in / out_degree_in)
WITH n, damping,
  (1 - damping) + damping * reduce(s = 0.0, in_node IN in_nodes |
    s + 1.0 / size((in_node)-[:FLIGHT]->())
  ) AS new_score
// Note : Cette approximation est simplifiée

RETURN n.node.iata_code AS airport, new_score AS score
ORDER BY score DESC
LIMIT 10;

// Note : Implémentation complète de PageRank en pur Cypher est très complexe
// Car nécessite boucles itératives qui ne sont pas supportées nativement

// ========================================
// ALGORITHME 2 : Degree Centrality (plus simple)
// ========================================

// 2a. Degree Centrality avec GDS
CALL gds.degree.stream('flights-network')
YIELD nodeId, score
RETURN
  gds.util.asNode(nodeId).iata_code AS airport,
  gds.util.asNode(nodeId).city AS city,
  score AS degree
ORDER BY degree DESC
LIMIT 10;

// 2b. Degree Centrality en Cypher 25 (facile !)
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
// ALGORITHME 3 : Betweenness Centrality
// ========================================

// 3a. Betweenness Centrality avec GDS
CALL gds.betweenness.stream('flights-network', {
  samplingSize: 100,  // Échantillonnage pour performance
  samplingSeed: 42
})
YIELD nodeId, score
RETURN
  gds.util.asNode(nodeId).iata_code AS airport,
  gds.util.asNode(nodeId).city AS city,
  score AS betweenness
ORDER BY betweenness DESC
LIMIT 10;

// 3b. Betweenness approximatif en Cypher 25
// Basé sur comptage de passages dans des plus courts chemins échantillonnés
CYPHER 25
WITH ['LAX', 'JFK', 'ATL', 'ORD', 'DEN', 'DFW', 'SFO', 'LAS', 'PHX', 'IAH'] AS hubs

// Pour chaque paire de hubs, trouver plus courts chemins
UNWIND hubs AS start_code
UNWIND hubs AS end_code
WITH start_code, end_code, hubs
WHERE start_code < end_code  // Éviter doublons et self-loops

MATCH (start:Airport {iata_code: start_code}), (end:Airport {iata_code: end_code})
MATCH paths = allShortestPaths((start)-[:FLIGHT*]-(end))

// Compter passages par chaque nœud intermédiaire
UNWIND nodes(paths)[1..-1] AS intermediate
WITH intermediate, count(*) AS passages
WHERE intermediate.iata_code IS NOT NULL

RETURN
  intermediate.iata_code AS airport,
  intermediate.city AS city,
  passages AS betweenness_score
ORDER BY betweenness_score DESC
LIMIT 10;

// ========================================
// ALGORITHME 4 : Closeness Centrality
// ========================================

// 4a. Closeness Centrality avec GDS
CALL gds.closeness.stream('flights-network')
YIELD nodeId, score
RETURN
  gds.util.asNode(nodeId).iata_code AS airport,
  gds.util.asNode(nodeId).city AS city,
  score AS closeness
ORDER BY closeness DESC
LIMIT 10;

// 4b. Closeness approximatif en Cypher 25
// Closeness = 1 / (somme des distances vers tous les autres nœuds)
CYPHER 25
MATCH (a:Airport)
WHERE size((a)-[:FLIGHT]-()) > 0  // Seulement aéroports connectés

// Calculer distance moyenne vers échantillon d'aéroports
WITH a, [(a)-[:FLIGHT*1..4]->(other:Airport) | length(path)] AS distances
WHERE size(distances) > 0

WITH a,
  1.0 / avg([d IN distances | toFloat(d)]) AS closeness_score

RETURN
  a.iata_code AS airport,
  a.city AS city,
  closeness_score
ORDER BY closeness_score DESC
LIMIT 10;

// ========================================
// ALGORITHME 5 : Community Detection (Louvain approximatif)
// ========================================

// 5a. Louvain avec GDS
CALL gds.louvain.stream('flights-network', {
  maxLevels: 10,
  maxIterations: 10
})
YIELD nodeId, communityId, intermediateCommunityIds
RETURN
  gds.util.asNode(nodeId).iata_code AS airport,
  gds.util.asNode(nodeId).state AS state,
  communityId
ORDER BY communityId, airport
LIMIT 20;

// 5b. Community Detection approximatif en Cypher 25
// Approche simple : regrouper par région géographique et densité de connexions
CYPHER 25
MATCH (a:Airport)
WITH a,
  // Identifier la région dominante (état le plus connecté)
  [(a)-[:FLIGHT]->(neighbor:Airport) | neighbor.state] AS neighbor_states
WHERE size(neighbor_states) > 0

WITH a,
  // Trouver l'état le plus fréquent parmi les voisins
  head([
    state IN apoc.coll.frequencies(neighbor_states)
    | state
  ] ORDER BY state.count DESC).item AS dominant_region

RETURN
  dominant_region AS community,
  collect(a.iata_code) AS airports,
  count(a) AS community_size
ORDER BY community_size DESC
LIMIT 10;

// ========================================
// ALGORITHME 6 : Triangle Count (Clustering Coefficient)
// ========================================

// 6a. Triangle Count avec GDS
CALL gds.triangleCount.stream('flights-network')
YIELD nodeId, triangleCount
WHERE triangleCount > 0
RETURN
  gds.util.asNode(nodeId).iata_code AS airport,
  gds.util.asNode(nodeId).city AS city,
  triangleCount
ORDER BY triangleCount DESC
LIMIT 10;

// 6b. Triangle Count en Cypher 25
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
// ALGORITHME 7 : Label Propagation (Community Detection alternatif)
// ========================================

// 7a. Label Propagation avec GDS
CALL gds.labelPropagation.stream('flights-network', {
  maxIterations: 10
})
YIELD nodeId, communityId
RETURN
  gds.util.asNode(nodeId).iata_code AS airport,
  gds.util.asNode(nodeId).state AS state,
  communityId
ORDER BY communityId, airport
LIMIT 20;

// 7b. Label Propagation approximatif en Cypher 25
// Utiliser l'état comme label initial et propager
CYPHER 25
MATCH (a:Airport)
MATCH (a)-[:FLIGHT]-(neighbor:Airport)
WITH a, neighbor.state AS neighbor_label
WITH a, neighbor_label, count(*) AS freq
ORDER BY freq DESC
WITH a, collect({label: neighbor_label, count: freq})[0].label AS propagated_label
RETURN
  propagated_label AS community,
  collect(a.iata_code) AS airports,
  count(a) AS size
ORDER BY size DESC
LIMIT 10;

// ========================================
// COMPARAISON : Performance et Précision
// ========================================

// Test : Degree Centrality (simple, devrait être identique)

// GDS
PROFILE
CALL gds.degree.stream('flights-network')
YIELD nodeId, score
RETURN count(*);

// Cypher 25
CYPHER 25
PROFILE
MATCH (a:Airport)
OPTIONAL MATCH (a)-[out:FLIGHT]->()
OPTIONAL MATCH (a)<-[in:FLIGHT]-()
RETURN count(DISTINCT a);

// ========================================
// CLEANUP
// ========================================

CALL gds.graph.drop('flights-network');

// ========================================
// POINTS CLÉS POUR LE RAPPORT
// ========================================

/*
1. ALGORITHMES FACILES À IMPLÉMENTER EN CYPHER 25 :

   a) Degree Centrality : ✅ Trivial
      - Simple COUNT des relations
      - Performance et résultats identiques à GDS

   b) Triangle Count : ✅ Simple
      - Pattern matching (a)->(b)->(c)->(a)
      - Performance OK sur graphes moyens

   c) Betweenness (approximatif) : ⚠️ Possible mais lent
      - Nécessite all shortest paths
      - Échantillonnage requis pour performance

2. ALGORITHMES DIFFICILES EN CYPHER 25 :

   a) PageRank : ❌ Très difficile
      - Nécessite itérations convergentes
      - Cypher ne supporte pas les vraies boucles
      - Devoir "dérouler" les itérations manuellement

   b) Louvain / Community Detection : ❌ Très complexe
      - Algorithme multi-phase itératif
      - Optimisation de modularité
      - Impraticable en pur Cypher

   c) Closeness Centrality : ⚠️ Approximation possible
      - Nécessite distances vers tous les nœuds
      - Échantillonnage requis

3. POURQUOI GDS EST MEILLEUR :

   a) Performance :
      - Implémentations en C++ optimisées
      - Parallélisation native
      - Structures de données efficaces
      - Speedup : 100x-1000x vs Cypher pur

   b) Précision :
      - Algorithmes exacts (pas d'approximations)
      - Convergence propre pour itératifs
      - Gestion de cas particuliers

   c) Facilité d'utilisation :
      - API simple et consistante
      - Paramètres ajustables
      - Mode stream/write/mutate

4. QUAND UTILISER CYPHER 25 vs GDS :

   Cypher 25 :
   - Métriques simples (degree, triangles)
   - Graphes petits (<10k nœuds)
   - Prototypage rapide
   - Pas besoin de projection

   GDS :
   - Algorithmes complexes (PageRank, Louvain)
   - Grands graphes (>100k nœuds)
   - Production
   - Performance critique

5. RÉSULTATS DE PERFORMANCE ATTENDUS :

   Sur notre graphe (312 aéroports, 107k vols) :

   Degree Centrality :
   - Cypher 25 : ~50ms
   - GDS : ~10ms
   - Ratio : ~5x

   Triangle Count :
   - Cypher 25 : ~500ms
   - GDS : ~50ms
   - Ratio : ~10x

   PageRank :
   - Cypher 25 : N/A (trop complexe)
   - GDS : ~100ms

   Betweenness :
   - Cypher 25 (échantillonné) : ~2s
   - GDS : ~200ms
   - Ratio : ~10x

6. POUR LE RAPPORT :

   a) Montrer implémentations côte à côte
      - Degree : identique
      - Betweenness : approximation vs exact

   b) Comparer PROFILE
      - db hits
      - Temps d'exécution
      - Operator complexity

   c) Expliquer limitations Cypher :
      - Pas de boucles while/for
      - Pas d'état mutable
      - Déclaratif vs impératif

   d) Montrer quand Cypher 25 suffit :
      - Métriques simples
      - Ad-hoc analyses
      - Petits graphes

   e) Montrer quand GDS est nécessaire :
      - Algorithmes itératifs
      - Production
      - Performance

   f) Conclusion :
      - Cypher 25 puissant pour certains algos
      - Mais GDS reste indispensable
      - Utiliser le bon outil pour le bon problème
*/
