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

// Version 1b: Approche alternative Cypher 5 avec reduce dans WHERE
// ATTENTION : C'est exactement le pattern problématique identifié dans SIGMOD !
MATCH path = (start:Airport {iata_code: 'LAX'})
  -[:FLIGHT*2..4]->(end:Airport {iata_code: 'JFK'})
WHERE all(i IN range(0, size(relationships(path))-2) WHERE
  relationships(path)[i].delay < relationships(path)[i+1].delay
)
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  [r IN relationships(path) | r.delay] AS delays,
  size(relationships(path)) AS hops
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
// VARIANTES : Autres propriétés croissantes
// ========================================

// 2a. Distance croissante (vols de plus en plus longs)
CYPHER 25
MATCH path = (start:Airport {iata_code: 'ATL'})
  -[:FLIGHT*2..4]->(end:Airport {iata_code: 'SEA'})
WHERE allReduce(
  prev_dist = 0,
  rel IN relationships(path) |
    CASE WHEN rel.distance > prev_dist THEN rel.distance ELSE null END,
  prev_dist IS NOT NULL
)
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  [r IN relationships(path) | r.distance] AS distances,
  size(relationships(path)) AS hops
LIMIT 5;

// 2b. Timestamp croissant (correspondances valides avec temps minimum)
CYPHER 25
MATCH path = (start:Airport {iata_code: 'LAX'})
  -[:FLIGHT*2..3]->(end:Airport {iata_code: 'BOS'})
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
  [r IN relationships(path) | {
    depart: toString(r.departure_ts),
    arrive: toString(r.arrival_ts)
  }] AS times,
  size(relationships(path)) AS hops
LIMIT 5;

// ========================================
// ANALYSE DE PERFORMANCE
// ========================================

// Mesurer le temps d'exécution avec PROFILE
// ATTENTION : Sur de grands graphes, la version Cypher 5 peut timeout !

// Test sur sous-graphe réduit (top 10 hubs seulement)
// Pour éviter le timeout mentionné dans SIGMOD

PROFILE
MATCH path = (start:Airport)
  -[:FLIGHT*2..3]->(end:Airport)
WHERE start.iata_code IN ['LAX', 'ATL', 'ORD', 'DEN', 'DFW', 'JFK', 'SFO', 'LAS', 'PHX', 'IAH']
  AND end.iata_code IN ['LAX', 'ATL', 'ORD', 'DEN', 'DFW', 'JFK', 'SFO', 'LAS', 'PHX', 'IAH']
  AND all(i IN range(0, size(relationships(path))-2) WHERE
    relationships(path)[i].delay < relationships(path)[i+1].delay
  )
RETURN count(path) AS cypher5_count;

CYPHER 25
PROFILE
MATCH path = (start:Airport)
  -[:FLIGHT*2..3]->(end:Airport)
WHERE start.iata_code IN ['LAX', 'ATL', 'ORD', 'DEN', 'DFW', 'JFK', 'SFO', 'LAS', 'PHX', 'IAH']
  AND end.iata_code IN ['LAX', 'ATL', 'ORD', 'DEN', 'DFW', 'JFK', 'SFO', 'LAS', 'PHX', 'IAH']
  AND allReduce(
    prev_delay = -999999.0,
    rel IN relationships(path) |
      CASE WHEN rel.delay > prev_delay THEN rel.delay ELSE null END,
    prev_delay IS NOT NULL
  )
RETURN count(path) AS cypher25_count;

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
