-- Simple verification: all trips on route '11' with increasing sequences
SELECT 
    t.trip_id,
    COUNT(*) AS stop_count,
    BOOL_AND(
        st.stop_sequence < LEAD(st.stop_sequence) 
        OVER (PARTITION BY st.trip_id ORDER BY st.stop_sequence)
    ) AS is_strictly_increasing
FROM trips t
JOIN routes r ON t.route_id = r.route_id
JOIN stop_times st ON t.trip_id = st.trip_id
WHERE r.route_long_name = '11'
GROUP BY t.trip_id
HAVING BOOL_AND(
    st.stop_sequence < LEAD(st.stop_sequence) 
    OVER (PARTITION BY st.trip_id ORDER BY st.stop_sequence)
) IS NOT FALSE
LIMIT 10;