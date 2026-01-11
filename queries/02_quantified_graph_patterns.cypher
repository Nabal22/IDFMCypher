// ========================================
// REQUÊTE 2 : QUANTIFIED GRAPH PATTERNS
// ========================================

// ========================================
// CAS D'USAGE 1 : Exactement N escales
// ========================================

// Cypher 25 : Trouver des chemins avec EXACTEMENT 2 escales (3 vols)
CYPHER 25
MATCH path = (start:Airport {iata_code: 'LAX'})
             (()-[:FLIGHT]->(:Airport)){3}
             (end:Airport {iata_code: 'JFK'})
WHERE allReduce(
    seen = [],
    n IN nodes(path) | seen + n,
    single(x IN seen WHERE x = n)
)
WITH [n IN nodes(path) | n.iata_code] AS route
RETURN route
LIMIT 10;

// Cypher 5 : Sans quantified patterns (plus verbeux)
// Doit spécifier explicitement 3 vols (2 escales)
CYPHER 5
MATCH path = (start:Airport {iata_code: 'LAX'})
  -[:FLIGHT]->(hub1:Airport)
  -[:FLIGHT]->(hub2:Airport)
  -[:FLIGHT]->(end:Airport {iata_code: 'JFK'})
WHERE start <> hub1 AND start <> hub2 AND start <> end
  AND hub1 <> hub2 AND hub1 <> end
  AND hub2 <> end
WITH DISTINCT [n IN nodes(path) | n.iata_code] AS route
RETURN route
LIMIT 10;

// si on ne met pas le LIMIT 10 la requête CYPHER 5 sera anormalement longue

// ========================================
// COMPARAISON : Avec vs Sans Quantified Patterns
// ========================================

// SANS quantified patterns (Cypher 5)
// Chemins de EXACTEMENT 3 hops
MATCH path1 = (s:Airport)-[:FLIGHT]->(a:Airport)-[:FLIGHT]->(b:Airport)-[:FLIGHT]->(e:Airport)
WHERE s.iata_code = 'LAX' AND e.iata_code = 'NYC'
RETURN [n IN nodes(path1) | n.iata_code] AS route_3hops
UNION

// Si on veut 2 OU 3 hops, il faut dupliquer la requête
MATCH path2 = (s:Airport)-[:FLIGHT]->(a:Airport)-[:FLIGHT]->(e:Airport)
WHERE s.iata_code = 'LAX' AND e.iata_code = 'NYC'
RETURN [n IN nodes(path2) | n.iata_code] AS route_2hops;

// AVEC quantified patterns (Cypher 25) : plus simple
CYPHER 25
MATCH path = (s:Airport {iata_code: 'LAX'})
  (()-->(:Airport)){2,3}
  (e:Airport {iata_code: 'NYC'})
RETURN
  [n IN nodes(path) | n.iata_code] AS route,
  size(relationships(path)) AS hops
ORDER BY hops;

// ========================================
// POINTS CLÉS POUR LE RAPPORT
// ========================================

/*
ANALYSE : QUANTIFIED GRAPH PATTERNS

1. SYNTAXE ET EXPRESSIVITÉ
   Cypher 5:  Doit énumérer explicitement chaque pattern
              → UNION pour combiner 2 hops + 3 hops
              → Code dupliqué, verbeux, difficile à maintenir

   Cypher 25: Quantification déclarative {n,m}
              → (pattern){2,3} exprime directement "2 ou 3 répétitions"
              → Code concis, DRY (Don't Repeat Yourself)

2. CAS D'USAGE DIFFICILES SANS QUANTIFIED PATTERNS
   - Range variable (2 à 10 hops) : impossible à écrire proprement en Cypher 5
   - Patterns complexes répétés : explosion de code
   - Modification du range : nécessite réécrire tous les UNIONs en Cypher 5

3. COMPARAISON AVEC SQL
   SQL WITH RECURSIVE:
   - Nécessite filtrage POST-TRAVERSÉE par hops BETWEEN n AND m
   - Doit fixer une limite supérieure arbitraire (AND fp.hops < 10)
   - Génère TOUS les chemins jusqu'à la limite, puis filtre

   Cypher 25 {n,m}:
   - Borne inférieure ET supérieure INTÉGRÉES dans le pattern
   - Pas de chemins générés en dehors de la range
   - Plus efficace (pruning automatique)

4. CONCLUSION
   Quantified patterns = sucre syntaxique ESSENTIEL
   - Simplifie l'écriture (5 lignes vs 20+ lignes en Cypher 5)
   - Améliore la lisibilité et maintenabilité
   - Performances meilleures (pas de UNION coûteux)
   - Fonctionnalité manquante cruciale en Cypher 5
*/
