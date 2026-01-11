WITH RECURSIVE flight_paths AS (

    SELECT 
        f.source,
        f.target,
        f.arrival_ts AS last_arrival_ts,
        f.delay AS last_delay,
        1 AS hops,

        ARRAY[f.source, f.target]::VARCHAR[] AS route, 
        ARRAY[f.delay]::NUMERIC[] AS delays,        
        
        f.delay::NUMERIC AS total_delay
    FROM flights f
    WHERE f.source = 'LAX'
    
    UNION ALL
    
    SELECT 
        fp.source,
        f.target,
        f.arrival_ts,
        f.delay,
        fp.hops + 1,
        fp.route || f.target,
        fp.delays || f.delay,
        fp.total_delay + f.delay
    FROM flights f
    INNER JOIN flight_paths fp ON f.source = fp.target
    WHERE 
        fp.hops < 4 
        AND f.delay > fp.last_delay 
        AND f.departure_ts > fp.last_arrival_ts 
)

SELECT 
    route,
    delays,
    hops,
    total_delay
FROM flight_paths
WHERE target = 'JFK' 
  AND hops BETWEEN 2 AND 4
LIMIT 50;