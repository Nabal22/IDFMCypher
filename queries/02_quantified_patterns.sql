-- Pattern 2: Quantified Graph Patterns - SQL VERSION
-- Objectif: Requêtes équivalentes avec agrégations et filtres SQL

-- ============================================================================
-- Arrêts avec au moins 3 correspondances rapides (<2 min)
-- ============================================================================

SELECT
  s.stop_name as hub,
  s.stop_id,
  COUNT(tf.to_stop_id) as fast_transfers
FROM stops s
JOIN transfers tf ON s.stop_id = tf.from_stop_id
WHERE tf.min_transfer_time < 120
  AND tf.min_transfer_time IS NOT NULL
GROUP BY s.stop_name, s.stop_id
HAVING COUNT(tf.to_stop_id) >= 3
ORDER BY fast_transfers DESC
LIMIT 20;

