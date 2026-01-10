// Pattern 3: Shortest Path Algorithms - Comparaison complète
// Objectif: Comparer Cypher 5, Cypher 25 et GDS pour les plus courts chemins
// Analyse: BFS unidirectionnel vs bidirectionnel, pondéré vs non pondéré

// ============================================================================
// SETUP: Identifier deux arrêts bien connectés pour les tests
// ============================================================================

// Trouver des arrêts avec beaucoup de correspondances (bons candidats)
MATCH (s:Stop)-[:TRANSFER]-()
WITH s, count(*) as transfer_count
ORDER BY transfer_count DESC
LIMIT 10
RETURN s.stop_name, s.stop_id, transfer_count;

// Pour les exemples ci-dessous, utilisons des arrêts réels de notre dataset
// À ajuster selon les résultats de la requête ci-dessus

// ============================================================================
// CYPHER 5 - shortestPath (non pondéré, BFS)
// ============================================================================

// Plus court chemin en nombre de sauts (hops)
MATCH (start:Stop), (end:Stop)
WHERE start.stop_name CONTAINS 'Châtelet'
  AND end.stop_name CONTAINS 'Gare'
  AND start.stop_id < end.stop_id
WITH start, end LIMIT 1

MATCH path = shortestPath((start)-[:TRANSFER|STOP_TIME*..15]-(end))
RETURN
  start.stop_name as from_stop,
  end.stop_name as to_stop,
  length(path) as hops,
  [n IN nodes(path) | n.stop_name] as path_stops,
  [r IN relationships(path) | type(r)] as path_types;

// ============================================================================
// CYPHER 5 - allShortestPaths (tous les chemins de longueur minimale)
// ============================================================================

MATCH (start:Stop), (end:Stop)
WHERE start.stop_name CONTAINS 'Châtelet'
  AND end.stop_name CONTAINS 'Gare'
  AND start.stop_id < end.stop_id
WITH start, end LIMIT 1

MATCH paths = allShortestPaths((start)-[:TRANSFER|STOP_TIME*..15]-(end))
RETURN
  start.stop_name as from_stop,
  end.stop_name as to_stop,
  count(paths) as path_count,
  length(paths) as hops
LIMIT 5;

// ============================================================================
// CYPHER 25 - SHORTEST avec pondération
// ============================================================================
// ATTENTION: Syntaxe Cypher 25 non encore disponible dans Neo4j Desktop 5.x

/*
MATCH (start:Stop {stop_name: 'Châtelet'}),
      (end:Stop {stop_name: 'Gare du Nord'})

MATCH path = SHORTEST 1 PATHS (start)-[:TRANSFER* (r | r.min_transfer_time)]-(end)
RETURN
  path,
  reduce(time = 0, r IN relationships(path) | time + r.min_transfer_time) as total_time,
  length(path) as hops;

// Top 3 plus courts chemins pondérés
MATCH (start:Stop {stop_name: 'Châtelet'}),
      (end:Stop {stop_name: 'Gare du Nord'})

MATCH paths = SHORTEST 3 PATHS (start)-[:TRANSFER* (r | r.min_transfer_time)]-(end)
RETURN paths,
  reduce(time = 0, r IN relationships(paths) | time + r.min_transfer_time) as total_time
ORDER BY total_time;
*/

// ============================================================================
// CYPHER 5 - Approximation du plus court chemin pondéré
// ============================================================================
// Sans SHORTEST de Cypher 25, on peut approximer avec des filtres

MATCH (start:Stop), (end:Stop)
WHERE start.stop_name CONTAINS 'Châtelet'
  AND end.stop_name CONTAINS 'Gare'
  AND start.stop_id < end.stop_id
WITH start, end LIMIT 1

MATCH path = (start)-[:TRANSFER*..10]-(end)
WHERE ALL(r IN relationships(path) WHERE r.min_transfer_time IS NOT NULL)
WITH path,
  reduce(time = 0, r IN relationships(path) | time + coalesce(r.min_transfer_time, 0)) as total_time
ORDER BY total_time ASC
LIMIT 5
RETURN
  [n IN nodes(path) | n.stop_name] as stops,
  length(path) as hops,
  total_time as seconds;

// ============================================================================
// ANALYSE DES ALGORITHMES UTILISÉS
// ============================================================================

// shortestPath avec PROFILE pour voir l'algorithme
PROFILE
MATCH (start:Stop), (end:Stop)
WHERE start.stop_name CONTAINS 'Châtelet'
  AND end.stop_name CONTAINS 'Gare'
  AND start.stop_id < end.stop_id
WITH start, end LIMIT 1
MATCH path = shortestPath((start)-[:TRANSFER*..10]-(end))
RETURN length(path);

// Questions à répondre:
// - Quel algorithme est utilisé? (ShortestPath, Expand, etc.)
// - BFS unidirectionnel ou bidirectionnel?
// - Combien de db hits?

// ============================================================================
// COMPARAISON: Différents types de relations
// ============================================================================

// Uniquement via TRANSFER
MATCH (start:Stop), (end:Stop)
WHERE start.stop_name CONTAINS 'Châtelet'
  AND end.stop_name CONTAINS 'Gare'
  AND start.stop_id < end.stop_id
WITH start, end LIMIT 1
MATCH path = shortestPath((start)-[:TRANSFER*..10]-(end))
RETURN 'TRANSFER only' as method, length(path) as hops;

// Via TRANSFER et STOP_TIME
MATCH (start:Stop), (end:Stop)
WHERE start.stop_name CONTAINS 'Châtelet'
  AND end.stop_name CONTAINS 'Gare'
  AND start.stop_id < end.stop_id
WITH start, end LIMIT 1
MATCH path = shortestPath((start)-[:TRANSFER|STOP_TIME*..10]-(end))
RETURN 'TRANSFER + STOP_TIME' as method, length(path) as hops;

// ============================================================================
// TEST DE PERFORMANCE: Augmenter la profondeur max
// ============================================================================

// Profondeur 5
MATCH (start:Stop), (end:Stop)
WHERE start.stop_name CONTAINS 'Châtelet'
  AND end.stop_name CONTAINS 'Gare'
  AND start.stop_id < end.stop_id
WITH start, end LIMIT 1
MATCH path = shortestPath((start)-[:TRANSFER*..5]-(end))
RETURN 'depth=5' as config, length(path) as hops;

// Profondeur 10
MATCH (start:Stop), (end:Stop)
WHERE start.stop_name CONTAINS 'Châtelet'
  AND end.stop_name CONTAINS 'Gare'
  AND start.stop_id < end.stop_id
WITH start, end LIMIT 1
MATCH path = shortestPath((start)-[:TRANSFER*..10]-(end))
RETURN 'depth=10' as config, length(path) as hops;

// Profondeur 15
MATCH (start:Stop), (end:Stop)
WHERE start.stop_name CONTAINS 'Châtelet'
  AND end.stop_name CONTAINS 'Gare'
  AND start.stop_id < end.stop_id
WITH start, end LIMIT 1
MATCH path = shortestPath((start)-[:TRANSFER*..15]-(end))
RETURN 'depth=15' as config, length(path) as hops;

// ============================================================================
// BIDIRECTIONAL vs UNIDIRECTIONAL
// ============================================================================
// Neo4j utilise BFS bidirectionnel par défaut pour shortestPath
// Pour forcer unidirectionnel, on peut utiliser une variable length path

// Bidirectionnel (par défaut avec shortestPath)
PROFILE
MATCH (start:Stop), (end:Stop)
WHERE start.stop_name CONTAINS 'Châtelet'
  AND end.stop_name CONTAINS 'Gare'
  AND start.stop_id < end.stop_id
WITH start, end LIMIT 1
MATCH path = shortestPath((start)-[:TRANSFER*]-(end))
RETURN length(path);

// Unidirectionnel (approximation avec MATCH simple)
PROFILE
MATCH (start:Stop), (end:Stop)
WHERE start.stop_name CONTAINS 'Châtelet'
  AND end.stop_name CONTAINS 'Gare'
  AND start.stop_id < end.stop_id
WITH start, end LIMIT 1
MATCH path = (start)-[:TRANSFER*1..5]-(end)
RETURN length(path) ORDER BY length(path) LIMIT 1;

// Comparer les db hits et le temps d'exécution

// Questions pour le rapport:
// 1. Quelle différence de performance entre uni et bidirectionnel?
// 2. À partir de quelle profondeur la différence est significative?
// 3. Quel algorithme Neo4j utilise (voir dans PROFILE)?
// 4. Impact de la pondération sur les performances?
