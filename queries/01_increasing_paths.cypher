// Pattern 1: Increasing Property Paths (Departure Times)
// Objectif: Trouver des chemins où les horaires de départ augmentent strictement
// Comparaison: Cypher 5 (problématique) vs Cypher 25 (allReduce) vs SQL (recursive)

// ============================================================================
// CYPHER 5 - VERSION PROBLÉMATIQUE (reduce dans WHERE)
// ============================================================================

// Recherche de trajets avec horaires croissants sur une ligne spécifique
MATCH (r:Route {route_long_name: '11'})
MATCH (t:Trip)-[:BELONGS_TO]->(r)

// 2. On cherche les chemins qui finissent par ces voyages
MATCH p = (start:Stop)-[:STOP_TIME*]->(t)
WHERE NOT EXISTS {
    WITH p
    UNWIND range(0, length(p)-2) AS i
    WITH relationships(p)[i] AS r1, relationships(p)[i+1] AS r2
    // Le filtre négatif : on exclut si la séquence n'augmente pas
    WHERE r1.stop_sequence >= r2.stop_sequence
    RETURN 1
}
RETURN p
LIMIT 10

// ============================================================================
// CYPHER 25 - VERSION OPTIMISÉE (allReduce)
// ============================================================================


/*
MATCH p = (start:Stop)-[:STOP_TIME*]->(end:Trip)
WHERE all(i IN range(0, length(p)-2)
    WHERE (relationships(p)[i]).stop_sequence < (relationships(p)[i+1]).stop_sequence
)
RETURN p
LIMIT 10
*/
