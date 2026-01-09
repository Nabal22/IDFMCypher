# Part 2: Query Development and Comparison

## Prerequisites
✅ Data must be loaded in PostgreSQL and Neo4j (see `docs/PART1.MD`)

## Objective
Compare Cypher 5 vs Cypher 25 vs SQL by:
1. Identifying problematic Cypher 5 patterns from SIGMOD
2. Rewriting them using Cypher 25 features
3. Creating SQL equivalents
4. Testing on IDFM transport data
5. Analyzing execution plans

## SIGMOD Key Findings (Synthesized)

### The Core Problem
Cypher 5's `reduce` function in WHERE clauses creates **NP-complete queries** that:
- Appear simple but are computationally intractable
- Timeout on tiny graphs (≥10 nodes for Hamiltonian, ≥27 for subset sum)
- 93% of programmers cannot predict their performance

### 6 Problematic Patterns

#### 1. Hamiltonian Path
Using `all()` and `size()` to find paths visiting all nodes exactly once
- **Timeout**: ≥10 nodes (p=0.2 density)
- **Issue**: Exponential complexity hidden in simple syntax

#### 2. Subset Sum
Aggregating edge properties to match target value
- **Timeout**: ≥27 nodes
- **Issue**: NP-complete even with shortest path semantics

#### 3. Data-Aware Path Queries
Checking property values along paths (e.g., increasing values)
- **Issue**: Horizontal aggregation over path elements in filters
- **Example**: Paths where timestamps are monotonically increasing

#### 4. Horizontal Aggregation
Reduce over path elements in WHERE clauses
- **Issue**: Creates exponential search spaces
- **Example**: Counting node types along a path

#### 5. Regular Path Queries (RPQs)
Patterns like `(aa)*` are hard to express without lists
- **Issue**: Complex list manipulation required
- **Better**: Dedicated RPQ syntax

#### 6. Trail Semantics
Patterns like `A*BA*` perform poorly with lists
- **Key Finding**: Trail semantics alone are OK (3× larger graphs, <1ms)
- **Problem**: Combining trails with list operations causes collapse

### Cypher 25 Solutions
- **Quantified graph patterns**: Safer alternative to reduce in WHERE
- **allReduce**: Structured pattern for path property checks
- **Dedicated RPQ syntax**: Instead of general reduce
- **Restricted reduce**: Only in RETURN/WITH, not WHERE
- **Trail semantics**: Native support without list overhead

### SQL Comparison Findings
- Trail patterns: SQL performs **worse** than Neo4j
- List-based queries: SQL **slightly better** but still times out
- **Key difference**: Harder to write problematic queries accidentally in SQL

## Applying SIGMOD Patterns to IDFM Data

### Pattern 1: Data-Aware Paths (Increasing Times)
**Problem**: Find routes where departure times strictly increase

**Cypher 5 (Problematic)**:
```cypher
MATCH p = (s1:Stop)-[:STOP_TIME*]->(t:Trip)
WHERE all(i IN range(0, size(relationships(p))-2) WHERE
  relationships(p)[i].departure_time < relationships(p)[i+1].departure_time)
RETURN p;
```
**Expected**: Timeout on complex routes

**Cypher 25 (Solution)**:
```cypher
MATCH p = (s1:Stop)-[:STOP_TIME*]->(t:Trip)
WHERE allReduce(
  r IN relationships(p) |
  r.departure_time,
  a, b | a < b
)
RETURN p;
```
**Expected**: Handles larger routes

**SQL (Recursive)**:
```sql
WITH RECURSIVE route_path AS (
  -- Base case
  SELECT stop_id, trip_id, stop_sequence, departure_time,
         ARRAY[stop_id] as path, 1 as length
  FROM stop_times WHERE stop_sequence = 0

  UNION ALL

  -- Recursive case
  SELECT st.stop_id, st.trip_id, st.stop_sequence, st.departure_time,
         rp.path || st.stop_id, rp.length + 1
  FROM route_path rp
  JOIN stop_times st ON rp.trip_id = st.trip_id
    AND st.stop_sequence = rp.stop_sequence + 1
  WHERE st.departure_time > rp.departure_time  -- Increasing constraint
)
SELECT * FROM route_path;
```

### Pattern 2: Hamiltonian-Style (Visit All Stations)
**Problem**: Route visiting all metro stations on a line exactly once

**Cypher 5 (Problematic)**:
```cypher
MATCH (r:Route {route_id: '100110'})  -- RER A
MATCH (s:Stop)-[:STOP_TIME]->(:Trip)-[:BELONGS_TO]->(r)
WITH collect(DISTINCT s) as all_stops, count(DISTINCT s) as target
MATCH p = (start:Stop)-[:STOP_TIME*]->(t:Trip)-[:BELONGS_TO]->(r)
WHERE size(nodes(p)) = target
  AND size(nodes(p)) = size(apoc.coll.toSet(nodes(p)))
RETURN p LIMIT 1;
```
**Expected**: Timeout at ≥10 stations

**Cypher 25 (Solution)**:
Use trail semantics to avoid revisiting nodes:
```cypher
MATCH (r:Route {route_id: '100110'})
MATCH p = TRAIL (start:Stop)-[:STOP_TIME*]->(t:Trip)-[:BELONGS_TO]->(r)
WHERE length(p) = <station_count>
RETURN p LIMIT 1;
```

### Pattern 3: Subset Sum (Transfer Time Budget)
**Problem**: Find transfers totaling exactly N minutes

**Cypher 5 (Problematic)**:
```cypher
MATCH p = (s1:Stop)-[:TRANSFER*]-(s2:Stop)
WHERE reduce(total = 0, r IN relationships(p) | total + r.min_transfer_time) = 15
RETURN p;
```
**Expected**: Timeout around 27 nodes

**Cypher 25 (Solution)**:
Move reduce to RETURN:
```cypher
MATCH p = (s1:Stop)-[:TRANSFER*..5]-(s2:Stop)
WITH p, reduce(total = 0, r IN relationships(p) | total + r.min_transfer_time) as total_time
WHERE total_time = 15
RETURN p;
```

### Pattern 4: RPQ (Same Route Type Sequence)
**Problem**: Sequences of same route type (bus-bus-bus)

**Cypher 25 (RPQ Syntax)**:
```cypher
MATCH (s1:Stop)-[:STOP_TIME]->(:Trip)-[:BELONGS_TO]->(r:Route {route_type: 3})+
-[:BELONGS_TO]<-(:Trip)<-[:STOP_TIME]-(s2:Stop)
RETURN s1, s2;
```

### Pattern 5: Trail with Specific Transfers
**Problem**: Routes including specific transfer stations

**Cypher 25 (Trail Semantics)**:
```cypher
MATCH (hub:Stop {stop_name: 'Châtelet'})
MATCH p = TRAIL (s1:Stop)-[:TRANSFER|STOP_TIME*]-(hub)-[:TRANSFER|STOP_TIME*]-(s2:Stop)
WHERE s1.stop_id < s2.stop_id
RETURN p LIMIT 100;
```

## 6 Mandatory Comparisons

### 1. Increasing Property Paths ✅
See Pattern 1 above (Cypher 5 NOT EXISTS vs Cypher 25 allReduce vs SQL recursive)

### 2. Quantified Graph Patterns
**Problem**: Find stops with at least 3 wheelchair-accessible routes

**Cypher 25**:
```cypher
MATCH (s:Stop)
WHERE EXISTS {
  MATCH (s)-[:STOP_TIME]->(:Trip {wheelchair_accessible: 1})-[:BELONGS_TO]->(r:Route)
} >= 3
RETURN s.stop_name, count(*) as accessible_routes;
```

**Cypher 5 (Harder)**:
```cypher
MATCH (s:Stop)-[:STOP_TIME]->(t:Trip {wheelchair_accessible: 1})-[:BELONGS_TO]->(r:Route)
WITH s, count(DISTINCT r) as accessible_routes
WHERE accessible_routes >= 3
RETURN s.stop_name, accessible_routes;
```

### 3. Shortest Path Algorithms
**Compare all variants**:

**Cypher 5 - shortestPath**:
```cypher
MATCH (s1:Stop {stop_name: 'Gare du Nord'}),
      (s2:Stop {stop_name: 'Châtelet'})
MATCH p = shortestPath((s1)-[:TRANSFER|STOP_TIME*]-(s2))
RETURN p, length(p) as hops;
```

**Cypher 25 - shortest with weight**:
```cypher
MATCH (s1:Stop {stop_name: 'Gare du Nord'}),
      (s2:Stop {stop_name: 'Châtelet'})
MATCH p = SHORTEST 1 PATHS (s1)-[:TRANSFER|STOP_TIME* (r WHERE r.min_transfer_time IS NOT NULL | r.min_transfer_time)]-(s2)
RETURN p, reduce(time = 0, r IN relationships(p) | time + r.min_transfer_time) as total_time;
```

**GDS - Dijkstra**:
```cypher
// First: Create projection
CALL gds.graph.project(
  'transport-network',
  'Stop',
  {TRANSFER: {properties: 'min_transfer_time'}}
);

// Then: Run Dijkstra
MATCH (s1:Stop {stop_name: 'Gare du Nord'}),
      (s2:Stop {stop_name: 'Châtelet'})
CALL gds.shortestPath.dijkstra.stream('transport-network', {
  sourceNode: s1,
  targetNode: s2,
  relationshipWeightProperty: 'min_transfer_time'
})
YIELD path, totalCost
RETURN path, totalCost;
```

**SQL - Recursive CTE**:
```sql
WITH RECURSIVE shortest_path AS (
  SELECT from_stop_id, to_stop_id, min_transfer_time as cost,
         ARRAY[from_stop_id, to_stop_id] as path
  FROM transfers
  WHERE from_stop_id = 'GARE_DU_NORD_ID'

  UNION

  SELECT sp.from_stop_id, t.to_stop_id, sp.cost + t.min_transfer_time,
         sp.path || t.to_stop_id
  FROM shortest_path sp
  JOIN transfers t ON sp.to_stop_id = t.from_stop_id
  WHERE NOT t.to_stop_id = ANY(sp.path)  -- Avoid cycles
)
SELECT * FROM shortest_path WHERE to_stop_id = 'CHATELET_ID'
ORDER BY cost LIMIT 1;
```

### 4. Implement GDS Algorithms in Cypher 25
**PageRank-style centrality for transfer hubs**:

**GDS Native**:
```cypher
CALL gds.pageRank.stream('transport-network')
YIELD nodeId, score
RETURN gds.util.asNode(nodeId).stop_name as stop, score
ORDER BY score DESC LIMIT 10;
```

**Cypher 25 Implementation**:
```cypher
// Simplified iterative PageRank
MATCH (s:Stop)
WITH collect(s) as all_stops
UNWIND all_stops as stop
MATCH (stop)-[:TRANSFER]-(neighbor)
WITH stop, count(neighbor) as degree, collect(neighbor) as neighbors
// ... iterative computation would follow
```

### 5. SQL Efficiency Comparison
Find queries where SQL outperforms Cypher:

**Simple aggregations**: SQL usually faster
```sql
SELECT route_short_name, COUNT(*) as trip_count
FROM trips t JOIN routes r ON t.route_id = r.route_id
GROUP BY route_short_name
ORDER BY trip_count DESC;
```

**Set operations**: SQL's INTERSECT, EXCEPT
**Window functions**: SQL more mature

### 6. Execution Plan Analysis
Use `EXPLAIN` and `PROFILE`:

```cypher
// Cypher
PROFILE MATCH (s1)-[:TRANSFER*]-(s2) RETURN count(*);

// Check for:
// - BFS vs Dijkstra
// - Unidirectional vs Bidirectional
// - Expand(All) vs Expand(Into)
```

## Performance Testing Strategy

### Start Small
1. Test on single route (10-30 stops)
2. Gradually increase to full line
3. Document timeout thresholds
4. Compare with SIGMOD benchmarks

### Measure Everything
- Query execution time
- Memory usage
- Number of results
- Timeout threshold (node count)

### Document Plans
- Screenshot/save execution plans
- Note algorithm choices (BFS, Dijkstra, etc.)
- Explain differences between Cypher 5/25/SQL

## Report Sections for Part 2
1. Query comparison tables (Cypher 5 vs 25 vs SQL)
2. Execution plans with analysis
3. Performance graphs (time vs graph size)
4. Reference to SIGMOD lessons
5. Explanation of why certain patterns fail
6. Discussion of BFS unidirectional vs bidirectional

## Next Steps
After query development, proceed to Phase 3: Analysis and Report Writing
