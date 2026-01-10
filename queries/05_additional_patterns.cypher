// Patterns Additionnels - Subset Sum, Trails, RPQ
// Objectif: Patterns problématiques identifiés dans SIGMOD
// Démonstration des limites de Cypher 5

// ============================================================================
// PATTERN: Subset Sum (Transfer Time Budget)
// ============================================================================
// Problème NP-complet: trouver des correspondances totalisant exactement N secondes
// Timeout attendu: ≥27 nœuds selon SIGMOD

// CYPHER 5 - VERSION PROBLÉMATIQUE (reduce dans WHERE)
// ATTENTION: Peut timeout même sur de petits graphes

MATCH path = (s1:Stop)-[:TRANSFER*2..5]-(s2:Stop)
WHERE reduce(total = 0, r IN relationships(path) | total + coalesce(r.min_transfer_time, 0)) = 300
  AND s1.stop_id < s2.stop_id
RETURN
  s1.stop_name as from_stop,
  s2.stop_name as to_stop,
  length(path) as transfers,
  reduce(total = 0, r IN relationships(path) | total + coalesce(r.min_transfer_time, 0)) as total_seconds
LIMIT 10;

// CYPHER 5 - VERSION ALTERNATIVE (reduce hors WHERE)
// Déplacer le calcul dans WITH pour éviter l'explosion combinatoire

MATCH path = (s1:Stop)-[:TRANSFER*2..5]-(s2:Stop)
WHERE s1.stop_id < s2.stop_id
WITH path,
  reduce(total = 0, r IN relationships(path) | total + coalesce(r.min_transfer_time, 0)) as total_time
WHERE total_time = 300
RETURN
  [n IN nodes(path) | n.stop_name] as stops,
  length(path) as transfers,
  total_time as seconds
LIMIT 10;

// VERSION APPROXIMATIVE: Trouver les chemins proches de N secondes (±10%)
MATCH path = (s1:Stop)-[:TRANSFER*2..5]-(s2:Stop)
WHERE s1.stop_id < s2.stop_id
WITH path,
  reduce(total = 0, r IN relationships(path) | total + coalesce(r.min_transfer_time, 0)) as total_time
WHERE total_time BETWEEN 270 AND 330  // 300 ± 10%
RETURN
  [n IN nodes(path) | n.stop_name] as stops,
  length(path) as transfers,
  total_time as seconds
ORDER BY abs(total_time - 300)
LIMIT 10;

// ============================================================================
// PATTERN: Trail Semantics
// ============================================================================
// Chemins sans répétition d'arêtes (mais nœuds peuvent être revisités)

// CYPHER 5 - Pas de support natif des trails
// Approximation avec vérification manuelle des relations

MATCH path = (s1:Stop)-[:TRANSFER*3..5]-(s2:Stop)
WHERE s1.stop_id < s2.stop_id
  AND size(relationships(path)) = size(apoc.coll.toSet(relationships(path)))  // Nécessite APOC
RETURN
  [n IN nodes(path) | n.stop_name] as stops,
  length(path) as hops
LIMIT 10;

// CYPHER 25 - TRAIL natif (syntaxe future)
/*
MATCH path = TRAIL (s1:Stop)-[:TRANSFER*3..5]-(s2:Stop)
WHERE s1.stop_id < s2.stop_id
RETURN
  [n IN nodes(path) | n.stop_name] as stops,
  length(path) as hops
LIMIT 10;
*/

// ============================================================================
// PATTERN: Regular Path Queries (RPQ)
// ============================================================================
// Séquences de patterns répétitifs

// Exemple: Séquences métro-bus-métro
MATCH path = (s1:Stop)-[:STOP_TIME]->(t1:Trip)-[:BELONGS_TO]->(r1:Route {route_type: 1}),
             (r1)<-[:BELONGS_TO]-(t2:Trip)<-[:STOP_TIME]-(s2:Stop),
             (s2)-[:STOP_TIME]->(t3:Trip)-[:BELONGS_TO]->(r2:Route {route_type: 3}),
             (r2)<-[:BELONGS_TO]-(t4:Trip)<-[:STOP_TIME]-(s3:Stop),
             (s3)-[:STOP_TIME]->(t5:Trip)-[:BELONGS_TO]->(r3:Route {route_type: 1})
RETURN
  s1.stop_name as start,
  s2.stop_name as metro_bus_interchange,
  s3.stop_name as bus_metro_interchange,
  r1.route_long_name as metro1,
  r2.route_long_name as bus,
  r3.route_long_name as metro2
LIMIT 10;

// CYPHER 25 - RPQ avec quantificateurs (syntaxe future)
/*
MATCH (s1:Stop)-[:STOP_TIME]->(:Trip)-[:BELONGS_TO]->(r:Route {route_type: 1})+
      -[:BELONGS_TO]<-(:Trip)<-[:STOP_TIME]-(s2:Stop)
RETURN s1.stop_name, s2.stop_name, count(r) as metro_lines;
*/

// ============================================================================
// PATTERN: Data-Aware Paths avec propriétés complexes
// ============================================================================

// Chemins où les temps de transfert diminuent (inverse de increasing)
MATCH path = (s1:Stop)-[:TRANSFER*2..4]-(s2:Stop)
WHERE s1.stop_id < s2.stop_id
WITH path, relationships(path) as rels
WHERE ALL(i IN range(0, size(rels)-2) WHERE
  coalesce(rels[i].min_transfer_time, 999) > coalesce(rels[i+1].min_transfer_time, 999)
)
RETURN
  [n IN nodes(path) | n.stop_name] as stops,
  [r IN rels | r.min_transfer_time] as transfer_times,
  length(path) as hops
LIMIT 5;

// Chemins alternant correspondances rapides/lentes
MATCH path = (s1:Stop)-[:TRANSFER*4]-(s2:Stop)
WHERE s1.stop_id < s2.stop_id
WITH path, relationships(path) as rels
WHERE ALL(i IN range(0, size(rels)-1) WHERE
  CASE WHEN i % 2 = 0
    THEN coalesce(rels[i].min_transfer_time, 999) < 120  // Rapide
    ELSE coalesce(rels[i].min_transfer_time, 0) >= 120   // Lent
  END
)
RETURN
  [n IN nodes(path) | n.stop_name] as stops,
  [r IN rels | r.min_transfer_time] as times
LIMIT 5;

// ============================================================================
// PATTERN: Hamiltonian-style (visite complète)
// ============================================================================
// Trouver un chemin visitant tous les arrêts d'une ligne exactement une fois
// ATTENTION: NP-complet, timeout attendu à ≥10 nœuds

// Version limitée à une petite ligne
MATCH (r:Route {route_long_name: '14'})  // Ligne courte
MATCH (s:Stop)-[:STOP_TIME]->(:Trip)-[:BELONGS_TO]->(r)
WITH collect(DISTINCT s) as all_stops, count(DISTINCT s) as target_count

// Chercher un chemin visitant tous ces arrêts
MATCH path = (start:Stop)-[:TRANSFER*]-(end:Stop)
WHERE start IN all_stops
  AND end IN all_stops
  AND size(nodes(path)) = target_count
  AND size(nodes(path)) = size(apoc.coll.toSet(nodes(path)))  // Tous différents
RETURN
  [n IN nodes(path) | n.stop_name] as complete_path,
  length(path) as hops
LIMIT 1;

// ============================================================================
// PATTERN: Counting dans les chemins
// ============================================================================

// Compter les arrêts accessibles PMR le long d'un chemin
MATCH path = (s1:Stop)-[:TRANSFER*3..5]-(s2:Stop)
WHERE s1.stop_id < s2.stop_id
WITH path,
  reduce(count = 0, n IN nodes(path) WHERE n:Stop |
    count + CASE WHEN n.wheelchair_boarding = 1 THEN 1 ELSE 0 END
  ) as accessible_count
WHERE accessible_count >= 2
RETURN
  [n IN nodes(path) | n.stop_name] as stops,
  accessible_count
LIMIT 10;

// Compter les types de relations traversées
MATCH path = (s1:Stop)-[:TRANSFER|PATHWAY*3..5]-(s2:Stop)
WHERE s1.stop_id < s2.stop_id
WITH path,
  reduce(transfers = 0, r IN relationships(path) |
    transfers + CASE WHEN type(r) = 'TRANSFER' THEN 1 ELSE 0 END
  ) as transfer_count,
  reduce(pathways = 0, r IN relationships(path) |
    pathways + CASE WHEN type(r) = 'PATHWAY' THEN 1 ELSE 0 END
  ) as pathway_count
WHERE transfer_count > 0 AND pathway_count > 0
RETURN
  [n IN nodes(path) | n.stop_name] as stops,
  transfer_count,
  pathway_count
LIMIT 10;

// ============================================================================
// PERFORMANCE TESTS
// ============================================================================

// Test Subset Sum - mesurer le timeout threshold
PROFILE
MATCH path = (s1:Stop)-[:TRANSFER*2]-(s2:Stop)
WHERE reduce(total = 0, r IN relationships(path) | total + coalesce(r.min_transfer_time, 0)) = 300
RETURN count(path);

PROFILE
MATCH path = (s1:Stop)-[:TRANSFER*3]-(s2:Stop)
WHERE reduce(total = 0, r IN relationships(path) | total + coalesce(r.min_transfer_time, 0)) = 300
RETURN count(path);

// Questions pour le rapport:
// 1. À quelle profondeur le subset sum timeout?
// 2. Différence de performance reduce dans WHERE vs WITH?
// 3. Impact des trails sur la performance?
// 4. Comparaison avec les résultats SIGMOD?
