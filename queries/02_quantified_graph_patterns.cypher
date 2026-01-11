// ========================================
// REQUÊTE 2 : QUANTIFIED GRAPH PATTERNS
// ========================================
// Fonctionnalité Cypher 25 : Patterns quantifiés {n,m}
// Permet d'exprimer des contraintes sur le nombre de répétitions
// de patterns dans un chemin

// ========================================
// CAS D'USAGE 1 : Exactement N escales
// ========================================

// Cypher 25 : Trouver des chemins avec EXACTEMENT 2 escales (3 vols)
CYPHER 25
MATCH path = (start:Airport {iata_code: 'LAX'})
  (()-[:FLIGHT]->(:Airport)){3}  // 3 vols = 2 escales
  (end:Airport {iata_code: 'JFK'})
WHERE ALL(n IN nodes(path) WHERE single(x IN nodes(path) WHERE x = n))  // Pas de cycle
WITH DISTINCT [n IN nodes(path) | n.iata_code] AS route
RETURN
  route,
  size(route) - 1 AS hops
LIMIT 10;

// Cypher 5 : Sans quantified patterns (plus verbeux)
// Doit spécifier explicitement 3 vols (2 escales)
MATCH path = (start:Airport {iata_code: 'LAX'})
  -[:FLIGHT]->(hub1:Airport)
  -[:FLIGHT]->(hub2:Airport)
  -[:FLIGHT]->(end:Airport {iata_code: 'JFK'})
WHERE start <> hub1 AND start <> hub2 AND start <> end
  AND hub1 <> hub2 AND hub1 <> end
  AND hub2 <> end
WITH DISTINCT [n IN nodes(path) | n.iata_code] AS route
RETURN
  route,
  size(route) - 1 AS hops
LIMIT 10;

// ========================================
// CAS D'USAGE 2 : Range de répétitions {n,m}
// ========================================

// Chemins avec 1 à 3 escales via de GRANDS aéroports (>5000 vols)
CYPHER 25
MATCH (big_hub:Airport)
WHERE size((big_hub)-[:FLIGHT]-()) > 5000
WITH collect(big_hub) AS hubs

MATCH path = (start:Airport {iata_code: 'LAX'})
  ((hub:Airport)-->(:Airport)){1,3}
  (end:Airport {iata_code: 'MIA'})
WHERE ALL(h IN nodes(path)[1..-1] WHERE h IN hubs)  // Tous les intermédiaires sont des gros hubs
  AND ALL(n IN nodes(path) WHERE single(x IN nodes(path) WHERE x = n))
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  size(relationships(path)) AS escales
ORDER BY escales
LIMIT 5;

// ========================================
// CAS D'USAGE 3 : REPEATABLE ELEMENTS
// ========================================
// Permet de revisiter les mêmes nœuds/relations
// Utile pour modéliser des scénarios réels complexes

// Exemple : Trouver des "tours" - chemins qui reviennent au point de départ
// avec au moins 2 vols différents
CYPHER 25
MATCH REPEATABLE ELEMENTS path = (start:Airport {iata_code: 'ATL'})
  ((intermediate)--(:Airport)){2,4}
  (start)
WHERE size(relationships(path)) >= 3
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  [r IN relationships(path) | {
    from: startNode(r).iata_code,
    to: endNode(r).iata_code,
    airline: r.airline,
    delay: r.delay
  }] AS flight_details,
  size(relationships(path)) AS total_flights
LIMIT 10;

// ========================================
// CAS D'USAGE 4 : Patterns complexes avec contraintes
// ========================================

// Trouver des chemins où on passe par AU MOINS 2 hubs majeurs
// (difficile à exprimer sans quantified patterns)
CYPHER 25
MATCH (major_hub:Airport)
WHERE size((major_hub)-->()) > 3000  // Départs > 3000
WITH collect(major_hub.iata_code) AS major_hubs

MATCH path = (start:Airport {iata_code: 'SFO'})
  (()-->(:Airport)){3,5}
  (end:Airport {iata_code: 'BOS'})
WHERE ALL(n IN nodes(path) WHERE single(x IN nodes(path) WHERE x = n))
  // Au moins 2 nœuds intermédiaires sont des hubs majeurs
  AND size([n IN nodes(path)[1..-1] WHERE n.iata_code IN major_hubs]) >= 2
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  [n IN nodes(path)[1..-1] WHERE n.iata_code IN major_hubs | n.iata_code] AS hubs_visited,
  size(relationships(path)) AS hops
ORDER BY hops
LIMIT 10;

// ========================================
// CAS D'USAGE 5 : Combinaison avec allReduce
// ========================================

// Chemins avec 2-3 escales où le retard total reste < 60 min
CYPHER 25
MATCH path = (start:Airport {iata_code: 'DEN'})
  (()-->(:Airport)){2,3}
  (end:Airport {iata_code: 'LAX'})
WHERE ALL(n IN nodes(path) WHERE single(x IN nodes(path) WHERE x = n))
  AND allReduce(
    total_delay = 0.0,
    rel IN relationships(path) |
      CASE
        WHEN total_delay + rel.delay <= 60.0
        THEN total_delay + rel.delay
        ELSE null
      END,
    total_delay IS NOT NULL AND total_delay <= 60.0
  )
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  reduce(sum = 0.0, r IN relationships(path) | sum + r.delay) AS total_delay,
  size(relationships(path)) AS hops
ORDER BY total_delay
LIMIT 10;

// ========================================
// COMPARAISON : Avec vs Sans Quantified Patterns
// ========================================

// SANS quantified patterns (Cypher 5) : verbeux et rigide
// Chemins de EXACTEMENT 3 hops
MATCH path1 = (s:Airport)-[:FLIGHT]->(a:Airport)-[:FLIGHT]->(b:Airport)-[:FLIGHT]->(e:Airport)
WHERE s.iata_code = 'LAX' AND e.iata_code = 'NYC'
RETURN [n IN nodes(path1) | n.iata_code] AS route_3hops
UNION
// Si on veut 2 OU 3 hops, il faut dupliquer la requête
MATCH path2 = (s:Airport)-[:FLIGHT]->(a:Airport)-[:FLIGHT]->(e:Airport)
WHERE s.iata_code = 'LAX' AND e.iata_code = 'NYC'
RETURN [n IN nodes(path2) | n.iata_code] AS route_2hops;

// AVEC quantified patterns (Cypher 25) : concis et flexible
CYPHER 25
MATCH path = (s:Airport {iata_code: 'LAX'})
  (()-->(:Airport)){2,3}
  (e:Airport {iata_code: 'NYC'})
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  size(relationships(path)) AS hops
ORDER BY hops;

// ========================================
// CAS D'USAGE 6 : Validation de correspondances
// ========================================

// Trouver tous les chemins valides (avec temps de correspondance)
// avec 2-4 vols, en une seule requête élégante
CYPHER 25
MATCH path = (start:Airport {iata_code: 'LAX'})
  ((hub)-->(next)){2,4}
  (end:Airport {iata_code: 'JFK'})
WHERE ALL(n IN nodes(path) WHERE single(x IN nodes(path) WHERE x = n))
  AND allReduce(
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
    airline: r.airline,
    depart: toString(r.departure_ts),
    arrive: toString(r.arrival_ts)
  }] AS flights,
  size(relationships(path)) AS num_flights
ORDER BY num_flights
LIMIT 10;

// ========================================
// ANALYSE DE PERFORMANCE
// ========================================

// Comparer le temps d'exécution avec et sans quantified patterns

// Version Cypher 5 (spécifier chaque longueur séparément)
PROFILE
MATCH path = (s:Airport {iata_code: 'ATL'})-[:FLIGHT*2..3]->(e:Airport {iata_code: 'LAX'})
RETURN count(path);

// Version Cypher 25 (une seule requête avec quantifier)
CYPHER 25
PROFILE
MATCH path = (s:Airport {iata_code: 'ATL'})
  (()-->(:Airport)){2,3}
  (e:Airport {iata_code: 'LAX'})
RETURN count(path);

// ========================================
// POINTS CLÉS POUR LE RAPPORT
// ========================================

/*
1. AVANTAGES DES QUANTIFIED PATTERNS :

   a) EXPRESSIVITÉ :
      - {n} : Exactement n répétitions
      - {n,m} : Entre n et m répétitions
      - {n,} : Au moins n répétitions
      - Plus concis que spécifier chaque longueur

   b) LISIBILITÉ :
      - Intent plus clair : "2 à 3 escales" vs union de patterns
      - Moins de duplication de code
      - Maintenance plus facile

   c) PERFORMANCE :
      - Une seule traversée vs multiples requêtes UNION
      - Optimiseur peut mieux planifier
      - Moins de db hits

2. SANS QUANTIFIED PATTERNS (Cypher 5) :

   a) Pour longueurs variables :
      - Utiliser variable length: -[:FLIGHT*2..3]->
      - Mais moins de contrôle sur la structure
      - Ou dupliquer la requête avec UNION

   b) Limitations :
      - Verbeux pour patterns complexes
      - Difficile d'exprimer "au moins N passages par type de nœud"
      - Pas de REPEATABLE ELEMENTS sans Cypher 25

3. CAS DIFFICILES SANS QUANTIFIERS :

   - "Au moins 2 hubs majeurs sur le chemin"
     → Nécessite post-filtering complexe en Cypher 5

   - "Tours" (retour au point de départ)
     → REPEATABLE ELEMENTS essentiel

   - "Exactement N escales via certains types d'aéroports"
     → Pattern très verbeux sans quantifiers

4. COMPARAISON AVEC SQL :

   SQL n'a PAS d'équivalent direct aux quantified patterns.
   Pour simuler :
   - Compter les nœuds dans la CTE récursive
   - Filtrer par hops = N ou hops BETWEEN n AND m
   - Beaucoup plus verbeux

5. POUR LE RAPPORT :

   - Montrer un cas "facile avec {n,m}, difficile sans"
   - Comparer longueur du code (LOC)
   - Montrer PROFILE des deux versions
   - Expliquer que c'est du "syntactic sugar" mais TRÈS utile
   - Référencer GQL standard ISO 2024
*/
