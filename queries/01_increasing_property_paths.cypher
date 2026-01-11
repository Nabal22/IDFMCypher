// ========================================
// REQUÊTE 1 : INCREASING PROPERTY PATHS
// ========================================
// Comparaison Cypher 5 vs Cypher 25
// Cas d'usage : Trouver des chemins de vols où le retard (delay) augmente à chaque escale
//
// Problématique SIGMOD : reduce() dans WHERE clause = NP-complet
// Solution Cypher 25 : allReduce() optimisé

// ========================================
// CYPHER 5 : NOT EXISTS (PROBLÉMATIQUE)
// ========================================
// Cette version utilise NOT EXISTS avec reduce pour vérifier que
// les retards sont croissants. Selon l'article SIGMOD, ce pattern
// peut causer des timeouts même sur de petits graphes.

// Version 1a: NOT EXISTS avec reduce (pattern problématique SIGMOD)
// Trouve les chemins LAX → JFK avec retards croissants
MATCH path = (start:Airport {iata_code: 'LAX'})
  -[:FLIGHT*2..4]->(end:Airport {iata_code: 'JFK'})
WHERE NOT EXISTS {
  // Vérifie qu'il n'existe PAS de paire de vols consécutifs où le retard décroît
  WITH path
  UNWIND range(0, size(relationships(path))-2) AS i
  WITH relationships(path) AS rels, i
  WHERE rels[i].delay >= rels[i+1].delay  // Retard qui décroît ou stagne
  RETURN 1
}
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  [r IN relationships(path) | r.delay] AS delays,
  size(relationships(path)) AS hops,
  reduce(total = 0, r IN relationships(path) | total + r.delay) AS total_delay
LIMIT 10;

// ========================================
// CYPHER 25 : allReduce (OPTIMISÉ)
// ========================================
// allReduce permet de vérifier la propriété croissante PENDANT
// la traversée du graphe, éliminant les chemins invalides tôt.
// Cela évite l'explosion combinatoire du Cypher 5.

CYPHER 25
MATCH path = (start:Airport {iata_code: 'LAX'})
  -[:FLIGHT*2..4]->(end:Airport {iata_code: 'JFK'})
WHERE allReduce(
  prev_delay = -999999.0,  // Initialiser avec une valeur très basse
  rel IN relationships(path) |
    CASE
      WHEN rel.delay > prev_delay THEN rel.delay
      ELSE null  // Si retard ne croît pas, renvoyer null pour invalider le chemin
    END,
  prev_delay IS NOT NULL  // Condition finale : tous les retards doivent être croissants
)
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  [r IN relationships(path) | r.delay] AS delays,
  size(relationships(path)) AS hops,
  reduce(total = 0.0, r IN relationships(path) | total + r.delay) AS total_delay
LIMIT 10;


// ========================================
// POINTS CLÉS POUR LE RAPPORT
// ========================================

/*
1. PROBLÈME (SIGMOD) :
   - reduce/all dans WHERE = évaluation APRÈS génération de tous les chemins
   - Explosion combinatoire : O(n^k) chemins pour k escales
   - Même avec 10 nœuds, timeout observé dans SIGMOD

2. SOLUTION (Cypher 25) :
   - allReduce évalue PENDANT la traversée (pruning précoce)
   - Élimine les branches invalides dès qu'un retard décroît
   - Réduit la complexité pratique de millions → milliers de chemins

3. RÉSULTATS ATTENDUS :
   - Cypher 5 : Timeout ou très lent (>100s) sur graphe complet
   - Cypher 25 : <2s même avec depth 4
   - Speedup : 120x selon l'article (AoC Day 12)

4. PLANS D'EXÉCUTION :
   - Cypher 5 : Expand All → Filter (post-processing)
   - Cypher 25 : Expand + Filter simultanés (stateful traversal)

5. DANS LE RAPPORT :
   - Montrer les deux requêtes côte à côte
   - Comparer les PROFILE (db hits, temps)
   - Expliquer pourquoi all() crée le problème NP-complet
   - Référencer SIGMOD Fig. 5 (Hamiltonian path timeout à 10 nœuds)
*/
