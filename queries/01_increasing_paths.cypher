// Pattern 1: Increasing Property Paths (Departure Times)
// Objectif: Trouver des chemins où les horaires de départ augmentent strictement
// Comparaison: Cypher 5 (problématique) vs Cypher 25 (allReduce) vs SQL (recursive)

// ============================================================================
// CYPHER 5 - VERSION PROBLÉMATIQUE (reduce dans WHERE)
// ============================================================================

CYPHER 5
MATCH (r:Route {route_long_name: '11'})
MATCH (t:Trip)-[:BELONGS_TO]->(r)

MATCH p = (start:Stop)-[:STOP_TIME*]->(t)
WHERE NOT EXISTS {
    WITH p
    UNWIND range(0, length(p)-2) AS i
    WITH relationships(p)[i] AS r1, relationships(p)[i+1] AS r2
    WHERE r1.stop_sequence >= r2.stop_sequence
    RETURN 1
}
RETURN p
LIMIT 10

// ============================================================================
// CYPHER 25 - VERSION AVEC allReduce
// ============================================================================

CYPHER 25
MATCH (r:Route {route_long_name: '11'})
MATCH (t:Trip)-[:BELONGS_TO]->(r)
MATCH p = (start:Stop)-[:STOP_TIME*]->(t)

// allReduce vérifie que TOUTES les transitions satisfont la condition
WHERE allReduce(
    prev = -1,
    rel IN relationships(p) |
    rel.stop_sequence,
    prev <= rel.stop_sequence
)
RETURN p
LIMIT 10