// Pattern 2: Quantified Graph Patterns
// Objectif: Démontrer l'expressivité des quantified patterns de Cypher 25
// Cas d'usage: Trouver les arrêts avec plusieurs lignes accessibles PMR

// ============================================================================
// CYPHER 5 - VERSION SANS QUANTIFIED PATTERNS (plus verbeuse)
// ============================================================================

// Arrêts avec au moins 3 correspondances rapides
MATCH (s:Stop)-[t:TRANSFER]->(dest:Stop)
WHERE t.min_transfer_time < 120 AND t.min_transfer_time IS NOT NULL
WITH s, count(dest) as fast_transfers
WHERE fast_transfers >= 3
RETURN
  s.stop_name as hub,
  s.stop_id,
  fast_transfers
ORDER BY fast_transfers DESC
LIMIT 20;

// ============================================================================
// CYPHER 25 - QUANTIFIED GRAPH PATTERNS (syntaxe moderne)
// ============================================================================

// Arrêts avec au moins 3 correspondances rapides (<2 min)
MATCH (s:Stop)
WITH s, count { 
  MATCH (s)-[t:TRANSFER]->() 
  WHERE t.min_transfer_time < 120
} as fast_transfers
WHERE fast_transfers >= 3
RETURN 
  s.stop_name as hub,
  s.stop_id,
  fast_transfers
ORDER BY fast_transfers DESC
LIMIT 20;

