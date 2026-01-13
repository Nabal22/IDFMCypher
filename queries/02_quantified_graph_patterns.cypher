// REQUÊTE 2 : QUANTIFIED GRAPH PATTERNS

// CAS D'USAGE 1 : Exactement N escales

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

// Cypher 5 : Sans quantified patterns
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


================================================================================
RÉSUMÉ POUR LE RAPPORT
================================================================================

QUANTIFIED PATTERNS : NOUVELLE SYNTAXE CYPHER 25

Avant (Cypher 5):
- Pattern matching explicite pour chaque saut
- Code verbeux (7 lignes pour 3 hops)
- Duplication nécessaire pour supporter des ranges (2 OU 3 hops → UNION)
- WHERE complexe pour éviter les cycles (6 comparaisons pour 3 hops)

Après (Cypher 25):
- Quantificateurs concis: {3} = exactement 3, {2,3} = entre 2 et 3
- Une seule ligne: (()-->(:Airport)){2,3}
- allReduce() pour détecter les cycles simplement
- Pas besoin de UNION pour gérer les ranges

RÉDUCTION DU CODE

| Cas d'usage              | Cypher 5      | Cypher 25    | Réduction |
|--------------------------|---------------|--------------|-----------|
| Exactement N hops        | 7 lignes      | 1 ligne      | 86%       |
| Range de hops (2-3)      | 2 requêtes    | 1 requête    | 50%       |
| Détection cycles         | 6 WHERE <>    | allReduce()  | Simplifié |

BÉNÉFICES

Lisibilité:
- Intent clair: {2,3} = "2 ou 3 sauts"
- Moins de code boilerplate
- Pas de variables intermédiaires (hub1, hub2, etc.)

Maintenabilité:
- Modifier N hops: changer un chiffre vs réécrire le pattern
- Ajouter range: changer {3} en {2,3} vs dupliquer la requête
- Moins d'erreurs possibles (oubli de WHERE <> dans Cypher 5)

Performance:
- Même complexité algorithmique
- Moteur Neo4j optimise les quantified patterns nativement
- Évite UNION (moins de passes sur les données)

CONCLUSION

Quantified patterns = sucre syntaxique puissant
→ Réduit code de 50-86% pour patterns répétitifs
→ Essentiel pour requêtes avec profondeur variable
→ Standard pour path queries modernes