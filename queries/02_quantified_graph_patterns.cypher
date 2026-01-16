// REQUÊTE 2 : QUANTIFIED GRAPH PATTERNS

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