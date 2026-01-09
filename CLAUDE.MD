# Project Context for Claude Code

## Project Overview
Master's level database project comparing Cypher 5 and Cypher 25 query languages using IDFM (Île-de-France Mobilités) public transport data from GTFS format.

## PART 1: Data Import and Modeling (CRITICAL - DO THIS FIRST!)

### Current Status
- GTFS data downloaded from https://transport.data.gouv.fr/resources/83316
- Need to import into both PostgreSQL and Neo4j

### Part 1 Requirements from CONSIGNES.MD

#### 1.1 Data Import Strategy
**Must implement in BOTH databases:**
- **PostgreSQL**: Relational schema with full GTFS data
- **Neo4j**: Graph model with nodes and relationships

**Key requirement**: Numeric properties on graph edges (travel_time, distance, cost, timestamps, etc.) to enable varied graph algorithms

#### 1.2 Data Cleaning
- Document any cleaning performed (nulls, duplicates, invalid data)
- Explain transformations in the report
- Preserve data integrity

#### 1.3 Modeling Decisions
**PostgreSQL Schema:**
- Proper normalization (likely already normalized in GTFS)
- Primary keys on all tables (stop_id, route_id, trip_id, etc.)
- Foreign keys (trips → routes, stop_times → trips, etc.)
- Check constraints (valid times, coordinates, wheelchair_boarding ∈ {0,1,2})
- Indexes on frequently queried columns

**Neo4j Graph Model - Critical Decisions:**

**Option A: Stop-Centric Model** (Recommended for path queries)
```
(:Stop)-[:CONNECTED_BY {trip_id, departure_time, arrival_time, travel_time}]->(:Stop)
(:Stop)-[:TRANSFER {min_transfer_time}]->(:Stop)
(:Stop)-[:PATHWAY {traversal_time, length}]->(:Stop)
```

**Option B: Trip-Centric Model**
```
(:Stop)<-[:STARTS_AT]-(:Trip)-[:ENDS_AT]->(:Stop)
(:Trip)-[:NEXT_STOP {stop_sequence, arrival_time, departure_time}]->(:Stop)
```

**Option C: Hybrid Model** (Most expressive)
```
(:Stop)-[:STOP_TIME {arrival_time, departure_time, stop_sequence}]-(:Trip)
(:Trip)-[:BELONGS_TO]->(:Route)
(:Route)-[:OPERATED_BY]->(:Agency)
(:Stop)-[:TRANSFER {min_transfer_time}]->(:Stop)
(:Stop)-[:PATHWAY {traversal_time, length}]->(:Stop)
```

**Choose based on:**
- Query patterns you want to optimize (shortest paths favor Stop-Centric)
- Memory constraints (stop_times.txt is 796 MB!)
- Whether you need trip-level vs stop-level queries

#### 1.4 Constraints and Indexes

**PostgreSQL:**
```sql
-- Primary Keys
ALTER TABLE stops ADD PRIMARY KEY (stop_id);
ALTER TABLE routes ADD PRIMARY KEY (route_id);
ALTER TABLE trips ADD PRIMARY KEY (trip_id);
ALTER TABLE stop_times ADD PRIMARY KEY (trip_id, stop_sequence);
ALTER TABLE transfers ADD PRIMARY KEY (from_stop_id, to_stop_id);

-- Foreign Keys
ALTER TABLE trips ADD FOREIGN KEY (route_id) REFERENCES routes(route_id);
ALTER TABLE stop_times ADD FOREIGN KEY (trip_id) REFERENCES trips(trip_id);
ALTER TABLE stop_times ADD FOREIGN KEY (stop_id) REFERENCES stops(stop_id);

-- Indexes for common queries
CREATE INDEX idx_stops_location ON stops(stop_lat, stop_lon);
CREATE INDEX idx_stop_times_stop ON stop_times(stop_id);
CREATE INDEX idx_trips_route ON trips(route_id);
```

**Neo4j:**
```cypher
// Uniqueness constraints (also create indexes)
CREATE CONSTRAINT stop_id_unique FOR (s:Stop) REQUIRE s.stop_id IS UNIQUE;
CREATE CONSTRAINT route_id_unique FOR (r:Route) REQUIRE r.route_id IS UNIQUE;
CREATE CONSTRAINT trip_id_unique FOR (t:Trip) REQUIRE t.trip_id IS UNIQUE;

// Existence constraints
CREATE CONSTRAINT stop_name_exists FOR (s:Stop) REQUIRE s.stop_name IS NOT NULL;

// Indexes for path queries
CREATE INDEX stop_location FOR (s:Stop) ON (s.stop_lat, s.stop_lon);
CREATE INDEX trip_route FOR (t:Trip) ON (t.route_id);
```

#### 1.5 Import Strategy

**PostgreSQL COPY approach:**
```sql
COPY stops FROM './export/stops.txt' CSV HEADER;
COPY routes FROM './export/routes.txt' CSV HEADER;
-- etc.
```

**Neo4j LOAD CSV approach:**
```cypher
// Load stops
LOAD CSV WITH HEADERS FROM 'file:///stops.txt' AS row
CREATE (:Stop {
  stop_id: row.stop_id,
  stop_name: row.stop_name,
  stop_lat: toFloat(row.stop_lat),
  stop_lon: toFloat(row.stop_lon),
  wheelchair_boarding: toInteger(row.wheelchair_boarding)
});

// Create relationships from stop_times
LOAD CSV WITH HEADERS FROM 'file:///stop_times.txt' AS row
MATCH (s1:Stop {stop_id: row.stop_id})
MATCH (t:Trip {trip_id: row.trip_id})
CREATE (s1)-[:STOP_TIME {
  arrival_time: row.arrival_time,
  departure_time: row.departure_time,
  stop_sequence: toInteger(row.stop_sequence)
}]->(t);
```

**WARNING**: stop_times.txt is 796 MB! Consider:
- Batch processing (PERIODIC COMMIT for old Neo4j, or batching for Neo4j 5+)
- Filtering to subset of data for initial testing
- Using `neo4j-admin import` for bulk loading

#### 1.6 Report Documentation for Part 1

Must explain:
1. **Modeling decisions**: Why you chose your graph model (reference course material)
2. **Import strategy**: Tools used, batch sizes, time taken
3. **Data cleaning**: Any issues found and how resolved
4. **Constraints**: All integrity constraints defined
5. **Indexes**: Which indexes created and why
6. **Trade-offs**: Memory vs performance, query optimization choices

### Common GTFS Import Pitfalls

**Time Format Issues:**
- GTFS times can exceed 24:00:00 (e.g., 25:30:00 for 1:30 AM next day)
- PostgreSQL TIME type won't accept this - use INTERVAL or custom parsing
- Neo4j: store as string or convert to minutes since midnight (integer)

**Large File Handling:**
- stop_times.txt (796 MB) may cause memory issues
- PostgreSQL: COPY is efficient, but consider batching if issues arise
- Neo4j: Use `CALL { ... } IN TRANSACTIONS OF 10000 ROWS` for batching
- Alternative: `neo4j-admin database import` for initial bulk load

**Relationship Creation Performance:**
- Creating relationships from stop_times requires matching stops and trips
- Without indexes, this is O(n²) - create constraints BEFORE loading relationships
- Consider creating derived relationships (NEXT_STOP) in separate pass

**Data Subsetting for Testing:**
```sql
-- PostgreSQL: Create subset for one route
CREATE TABLE stops_subset AS
SELECT DISTINCT s.* FROM stops s
JOIN stop_times st ON s.stop_id = st.stop_id
JOIN trips t ON st.trip_id = t.trip_id
WHERE t.route_id = 'ROUTE_ID_HERE';
```

**Calculating Derived Properties:**
You'll need to calculate `travel_time` for edges:
```sql
-- PostgreSQL: Calculate travel time between consecutive stops
WITH ordered_stops AS (
  SELECT trip_id, stop_id, stop_sequence,
         departure_time, arrival_time,
         LEAD(arrival_time) OVER (PARTITION BY trip_id ORDER BY stop_sequence) as next_arrival
  FROM stop_times
)
SELECT trip_id, stop_sequence,
       next_arrival - departure_time as travel_time
FROM ordered_stops;
```

### Next Steps for Part 1

1. **Explore the downloaded data** - examine file sizes, record counts, data quality
2. **Design schemas** for both PostgreSQL and Neo4j
3. **Decide on graph model** (Stop-Centric vs Hybrid - consider query needs)
4. **Write import scripts** (SQL for Postgres, Cypher for Neo4j)
5. **Test on small subset** first (e.g., one or two routes, one day)
6. **Verify data integrity** (counts match, relationships valid, no orphans)
7. **Create constraints and indexes** (BEFORE large-scale relationship creation)
8. **Import full dataset** with batching for large files
9. **Calculate derived properties** (travel_time between stops)
10. **Validate with simple queries** (count nodes, relationships, check connectivity)
11. **Document everything** for the report (decisions, issues, solutions)


## CRITICAL WORKFLOW - Start Here!

**The central objective of this project is to compare Cypher 5 with Cypher 25 using a specific methodology:**

### Step 1: Understand SIGMOD.MD Findings
`article/SIGMOD.MD` identifies critical problems with Cypher 5's list processing (`reduce` function):

**The Core Problem:**
- List operations with `reduce` in WHERE clauses create **NP-complete** queries that appear simple
- Queries timeout on tiny graphs (≥10 nodes for Hamiltonian path, 27 nodes for subset sum)
- Programmers cannot predict performance - 93% overestimate timeout thresholds by 2-3 orders of magnitude

**Problematic Query Patterns Identified:**
1. **Hamiltonian Path** - Using `all()` and `size()` (basic reduce variants)
2. **Subset Sum** - Even with shortest path semantics
3. **Data-aware path queries** - Checking property values along paths (e.g., increasing values)
4. **Horizontal aggregation** - Over path elements in filters
5. **Regular Path Queries (RPQs)** - Patterns like `(aa)*`
6. **Trail semantics patterns** - `A*BA*` style queries

**Key Finding:** List operations cause performance collapse, not trail semantics alone.

### Step 2: Propose Cypher 25 Rewrites
Using insights from `article/QUERY_CHOMP_REPEAT.MD` and `article/SOLVE_HARD_GRAPH_PROBLEMS_WITH_CYPHER_25.MD`:

**Cypher 25 Solutions:**
- **Quantified graph patterns** - Safer alternative to reduce in WHERE clauses
- **allReduce** - Structured pattern for path property checks
- **Dedicated RPQ syntax** - Instead of general reduce
- **Restricted reduce usage** - Only in RETURN/WITH, not WHERE
- **Specialized constructs** - For specific graph problems

**Your Task:**
- Take the problematic Cypher 5 patterns from SIGMOD.MD
- Rewrite them using Cypher 25 features
- Apply to IDFM transport dataset
- Compare performance and expressiveness

### Step 3: Compare and Test
- Test both Cypher 5 and Cypher 25 versions on the dataset
- Create SQL equivalents for PostgreSQL comparison
- **Expected behavior**: Some Cypher 5 queries will timeout (per SIGMOD findings)
- When queries don't terminate, find subset of data where they do
- Include execution plans showing algorithmic differences

### Important Notes
- SIGMOD.MD shows SQL performs slightly better but still times out on tiny graphs
- Focus on queries with different syntax but equivalent semantics
- Most interesting: when Cypher 25 version evaluates well but Cypher 5 doesn't
- The transport network is perfect for testing these patterns (paths, trails, connectivity)


## SIGMOD Problematic Patterns Applied to IDFM Dataset

Based on SIGMOD.MD findings, here's how to apply those problematic patterns to your transport data:

### Pattern 1: Data-Aware Path Queries (Increasing Values)
**SIGMOD Issue**: Using `reduce` in WHERE to check property monotonicity is NP-complete
**IDFM Application**: Find routes where departure times are strictly increasing
- **Cypher 5 (Problematic)**: Use `all()` with `reduce` over path relationships
- **Cypher 25 (Solution)**: Use `allReduce` or quantified patterns
- **Expected**: Cypher 5 may timeout on complex route networks

### Pattern 2: Hamiltonian-Style Queries
**SIGMOD Issue**: Finding paths visiting all nodes exactly once using `size()` and `all()`
**IDFM Application**: Find a route visiting all metro stations on a line exactly once
- **Cypher 5 (Problematic)**: Filter with list operations checking node uniqueness
- **Cypher 25 (Solution)**: Use trail semantics or quantified patterns
- **Expected**: Timeout on ≥10 stations per SIGMOD findings

### Pattern 3: Subset Sum-Style Queries
**SIGMOD Issue**: Aggregating edge properties to match a target value
**IDFM Application**: Find transfers totaling exactly N minutes
- **Cypher 5 (Problematic)**: Use `reduce` to sum transfer times in WHERE
- **Cypher 25 (Solution)**: Move reduce to RETURN/WITH, use other filters
- **Expected**: Timeout around 27 nodes per SIGMOD

### Pattern 4: Regular Path Queries (RPQs)
**SIGMOD Issue**: Patterns like `(aa)*` hard to express without lists
**IDFM Application**: Sequences of same route type (bus-bus-bus or metro-metro-metro)
- **Cypher 5 (Problematic)**: Complex list manipulation
- **Cypher 25 (Solution)**: Dedicated RPQ syntax
- **Expected**: Better expressiveness and performance

### Pattern 5: Trail Semantics
**SIGMOD Issue**: `A*BA*` patterns perform poorly with lists
**IDFM Application**: Routes that include specific transfer stations
- **Cypher 5**: List-based filtering
- **Cypher 25**: Native trail support
- **Key**: Trail semantics alone OK, but combined with lists causes collapse

## Mandatory Query Comparisons

### 1. Increasing Property Paths (REQUIRED)
**Maps to SIGMOD Pattern 1 above**
- For an edge property (departure_time, arrival_time, transfer_time)
- Filter paths where property values are **increasing** along edges
- **Cypher 5**: Use NOT EXISTS with reduce in WHERE (problematic per SIGMOD)
- **Cypher 25**: Use allReduce function (safe alternative)
- **SQL**: Provide equivalent recursive query
- **Test**: Compare performance - expect Cypher 5 timeout, Cypher 25 success

### 2. Quantified Graph Patterns (REQUIRED)
- At least one Cypher 25 query using quantified graph patterns
- Must be difficult to write without this feature
- Try to provide an alternative version without quantified patterns if possible

### 3. Shortest Path Algorithms (REQUIRED)
- Calculate shortest paths (weighted and unweighted)
- Test ALL variants in Cypher 5, Cypher 25, and GDS
- For GDS: create projection of transactional graph first
- **Analyze execution plans**: What algorithms does Neo4j use?
- **Comment specifically** on BFS unidirectional vs bidirectional

### 4. Implement GDS Algorithms in Cypher 25 (REQUIRED)
- Directly implement some GDS graph algorithms in Cypher 25
- Compare the two approaches (native GDS vs Cypher 25 implementation)

### 5. SQL Comparisons (REQUIRED)
- For each query, propose an SQL equivalent
- At least one recursive SQL query (compare with Cypher equivalent)
- Find at least one query where SQL is more efficient than Cypher
- Explain the results

### 6. Execution Plans (REQUIRED)
- Include several execution plans in the report
- Draw conclusions from the plans
- Compare equivalent Cypher 5 vs 25 queries with different syntax

## Dataset - IDFM GTFS

### Source
- **URL**: https://transport.data.gouv.fr/resources/83316
- **Period**: December 27, 2025 to January 28, 2026
- **Version**: 20251231_200102

### Key Files (with sizes)
- `stop_times.txt` (796.5 MB) - **VERY LARGE** - Trip schedules
- `trips.txt` (33.7 MB) - Individual trips on routes
- `transfers.txt` (6.2 MB) - Transfer connections between stops
- `stops.txt` (3.5 MB) - Stop locations and details
- `pathways.txt` (359.7 KB) - Pedestrian paths within stations
- `routes.txt` (79.3 KB) - Transit lines
- `calendar.txt` + `calendar_dates.txt` - Service schedules and exceptions
- `agency.txt` - Transit agencies (RATP, Aérobus)

### Graph-Relevant Properties
- **Numeric edge properties**: travel time, transfer time, pathway traversal time, departure/arrival times, distances
- **Node properties**: stop locations (lat/lon), wheelchair accessibility, stop types
- **Temporal aspects**: schedules, service calendars, time windows

## Database Implementations Required

### PostgreSQL (Relational)
- Full GTFS data with proper normalization
- **Constraints**: Primary keys, foreign keys, check constraints
- **Indexes**: Strategy must be explained in report
- Used for SQL query comparison

### Neo4j (Graph)
- Graph model of transport network
- **Critical**: Numeric properties on edges (times, distances, etc.)
- **Constraints**: Uniqueness, existence constraints
- **Indexes**: Node and relationship indexes
- Must support both Cypher 5 and Cypher 25 syntax

### Neo4j GDS (Graph Data Science)
- Create graph projections from transactional graph
- Use for native shortest path and other algorithms
- Compare with Cypher 25 implementations

## Report Requirements (French)

Must include:
1. **Data import strategy** - How data was loaded into both databases
2. **Data cleaning process** - Any transformations or cleaning performed
3. **Modeling decisions** - Why certain choices were made (reference course materials)
4. **Integrity constraints and indexes** - Complete documentation
5. **Execution plans** - Several examples with analysis
6. **Query comparisons** - All mandatory comparisons above
7. **Performance analysis** - Conclusions about Cypher 5 vs 25 vs SQL
8. **Explanations** - Why certain queries perform better/worse

## Technology Stack

### Required
- **Graph DB**: Neo4j (supports Cypher 5 & Cypher 25)
- **Relational DB**: PostgreSQL
- **Graph Algorithms**: Neo4j GDS

### Bonus (Optional)
- **Memgraph**: Alternative Cypher implementation
- **DuckDB**: SQL PGQ (Property Graph Queries in SQL)

## Graph Modeling Considerations

### For Transport Network
- **Stops** → Nodes
- **Routes/Trips** → Could be nodes or paths through stop nodes
- **Transfers** → Relationships between stops (with transfer_time property)
- **Pathways** → Relationships within stations (with traversal_time, length)
- **Trip segments** → Relationships with departure_time, arrival_time

### Properties to Include
- **On edges**: travel_time, transfer_time, traversal_time, distance, departure_time, arrival_time
- **On nodes**: stop_name, location (lat/lon), wheelchair_boarding, stop_type, route_type

### Constraints and Indexes
- Unique constraints on stop_id, route_id, trip_id
- Indexes on frequently queried properties
- Consider composite indexes for path queries

## Query Ideas for Transport Network

### Path-Based Queries
- Shortest travel time between two stops
- Paths with increasing departure times (monotonic temporal paths)
- Routes with accessibility constraints (wheelchair-only paths)
- Multi-modal journeys (bus → metro → train transfers)

### Reachability Queries
- All stops reachable within N minutes
- Stops reachable within a time window
- Connected components of the network

### Analysis Queries
- Transfer network analysis (hub detection)
- Service frequency by route
- Critical pathways (most-used transfers)

### Algorithm Queries
- Shortest path (unweighted: # of stops, weighted: travel time)
- All shortest paths between two stops
- K-shortest paths
- Dijkstra variants

## Performance Expectations (from SIGMOD.MD)

### What to Expect When Testing

**Cypher 5 Problematic Patterns:**
- Hamiltonian-style queries: timeout at **≥10 nodes** (for p=0.2 density)
- Subset sum queries: timeout at **≥27 nodes**
- Trail with lists (`A*BA*` + reduce): major performance degradation
- Data-aware paths with reduce: exponential complexity

**Cypher 25 Improvements:**
- Quantified patterns: should handle larger graphs
- allReduce: structured, predictable performance
- Trail semantics without lists: **3× larger graphs** with <1ms runtime
- Dedicated RPQ syntax: efficient compilation

**SQL Performance:**
- Trail patterns: **worse** than Neo4j
- List-based queries: **slightly better** than Cypher 5 but still timeouts
- Harder to write problematic queries accidentally
- Recursive queries may compete well for simple paths

### Testing Strategy
1. Start with small subgraphs (10-30 nodes)
2. Gradually increase size to find timeout thresholds
3. Document where each query pattern breaks
4. Compare actual thresholds with SIGMOD findings
5. Use execution plans to understand algorithmic differences

## Project Workflow Order

### Phase 1: Data Import (DO THIS FIRST!)
1. **Design schemas** for PostgreSQL and Neo4j (see "PART 1" section above)
2. **Write import scripts** and test on small data subset
3. **Define constraints and indexes** for both databases
4. **Import full dataset** (be mindful of 796 MB stop_times.txt)
5. **Verify data integrity** (record counts, relationship validity)
6. **Document modeling decisions** for the report

### Phase 2: Query Development
1. **Study the articles** to understand problematic patterns and solutions
2. **Start with simple queries** to verify data model works
3. **Implement mandatory comparisons** (see "Mandatory Query Comparisons" section)
4. **Test SIGMOD patterns** on your data (see "SIGMOD Problematic Patterns" section)
5. **Create SQL equivalents** for all Cypher queries
6. **Collect execution plans** for analysis

### Phase 3: Analysis and Report
1. **Compare performance** across Cypher 5, Cypher 25, SQL, and GDS
2. **Explain differences** using SIGMOD lessons and execution plans
3. **Document findings** in French report
4. **Include all required sections** (see "Report Requirements" section)

## When Working on This Project

1. **PART 1 BEFORE PART 2**: Cannot write queries without data!
2. **Both implementations required**: PostgreSQL AND Neo4j
3. **Execution plans are critical** - include in report with analysis
4. **Explain performance differences** - don't just report numbers (reference SIGMOD)
5. **Consider scalability** - stop_times.txt is 796 MB (may need subsetting for testing)
6. **Document everything** - modeling choices, import strategy, cleaning steps
7. **Compare fairly** - equivalent queries, appropriate indexes on both databases
8. **Handle non-terminating queries** - find subset where they work (expected per SIGMOD)
9. **Reference SIGMOD lessons** - explain why certain patterns fail
10. **Test incrementally** - small data → full data, simple queries → complex queries

## Important Reminders for Claude Code

### Core Methodology
- This is not a general Cypher 5 vs 25 comparison
- Must follow article-based methodology: identify SIGMOD problems → propose Cypher 25 solutions
- Focus on **6 problematic patterns** from SIGMOD.MD (see "SIGMOD Problematic Patterns" section)

### SIGMOD Key Insights
- **reduce in WHERE clauses = danger** - causes NP-complete queries
- **Timeouts are expected** for Cypher 5 patterns (this validates SIGMOD findings)
- **Cypher 25 solutions**: quantified patterns, allReduce, dedicated constructs
- **93% of programmers misjudge** these query costs - document this in your report

### Dataset Advantages
- Transport network is ideal for testing SIGMOD patterns
- Has all needed properties: paths, trails, numeric edge weights, temporal constraints
- Large enough to demonstrate timeouts (796 MB stop_times.txt)
- Real-world connected data (not synthetic)

### Query Design Guidelines
- Avoid reduce in WHERE (Cypher 5 style) - test it to show it fails
- Use quantified patterns and allReduce (Cypher 25 style) - show they succeed
- Create SQL equivalents - expect them to also struggle on problematic patterns
- Document execution plans - show algorithmic differences (BFS uni vs bidirectional)

### Article Reading
- SIGMOD.MD is now synthesized - core findings are in this CLAUDE.MD
- Read other two articles only when implementing specific Cypher 25 features
- Reference SIGMOD lessons in your report to explain results
