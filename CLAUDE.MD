# Project Context for Claude Code

## Project Overview
Master's level database project comparing Cypher 5 and Cypher 25 query languages using IDFM (Île-de-France Mobilités) public transport data from GTFS format.

## Quick Reference
- **Current Phase**: Part 1 - Data Import and Modeling
- **Dataset**: GTFS export in `export/` folder (796 MB stop_times.csv!)
- **Target Databases**: PostgreSQL (relational) + Neo4j (graph)
- **Documentation**: See `docs/` folder for detailed guides

## Project Structure

```
├── CLAUDE.MD           ← You are here (high-level overview)
├── CONSIGNES.MD        ← Assignment requirements (French)
├── RAPPORT.md          ← Report (to be written)
├── docs/
│   ├── PART1.MD        ← Data import guide (schemas, constraints, examples)
│   ├── PART2.MD        ← Query patterns and SIGMOD findings
│   └── DATASETS.MD     ← GTFS data structure reference
├── article/
│   ├── SIGMOD.MD       ← Synthesized findings on Cypher 5 problems
│   ├── QUERY_CHOMP_REPEAT.MD
│   └── SOLVE_HARD_GRAPH_PROBLEMS_WITH_CYPHER_25.MD
└── export/             ← GTFS data files
```

## 3-Phase Workflow

### Phase 1: Data Import (DO THIS FIRST!) 📊
**Status**: Not started
**Goal**: Load GTFS data into PostgreSQL and Neo4j

**Quick Steps**:
1. Design schemas (see `docs/PART1.MD` for options)
2. Create import scripts
3. Test on small subset first
4. Define constraints and indexes
5. Import full dataset
6. Validate with simple queries

**Key Decision**: Choose graph model (Stop-Centric vs Hybrid)
**Read**: `docs/PART1.MD` for detailed import guide

### Phase 2: Query Development 🔍
**Status**: Blocked (needs Phase 1)
**Goal**: Implement Cypher 5, Cypher 25, and SQL queries

**Quick Steps**:
1. Identify problematic Cypher 5 patterns from SIGMOD
2. Rewrite using Cypher 25 features
3. Create SQL equivalents
4. Test on IDFM data
5. Collect execution plans

**Read**: `docs/PART2.MD` for query patterns and SIGMOD findings

### Phase 3: Analysis & Report 📝
**Status**: Blocked (needs Phase 2)
**Goal**: Compare performance and write report

**Quick Steps**:
1. Compare Cypher 5 vs 25 vs SQL vs GDS
2. Analyze execution plans
3. Explain performance using SIGMOD lessons
4. Write French report

## Critical Information

### SIGMOD Core Finding
**Problem**: Cypher 5's `reduce` in WHERE clauses creates NP-complete queries
- Hamiltonian path: timeout at ≥10 nodes
- Subset sum: timeout at ≥27 nodes
- 93% of programmers misjudge query costs

**Solution**: Cypher 25 uses quantified patterns, allReduce, dedicated constructs

### 6 Mandatory Query Comparisons
1. **Increasing property paths** (NOT EXISTS vs allReduce)
2. **Quantified graph patterns** (Cypher 25 feature)
3. **Shortest path algorithms** (Cypher 5, 25, GDS comparison)
4. **GDS algorithms in Cypher 25** (implement directly)
5. **SQL comparisons** (including recursive queries)
6. **Execution plans** (analyze BFS uni vs bidirectional)

### Dataset Characteristics
- **Transport network**: Perfect for graph algorithms (paths, connectivity)
- **Numeric edges**: travel_time, transfer_time, traversal_time
- **Real-world**: IDFM Île-de-France public transport

## When Working With Claude

### I Should Prioritize
1. **Part 1 before Part 2** - Cannot query without data
2. **Test incrementally** - Small subset → full data
3. **Document decisions** - Modeling choices for report
4. **Reference SIGMOD** - Explain why patterns fail
5. **Execution plans** - Show algorithmic differences

### Key Files to Reference
- `docs/PART1.MD` - When working on data import
- `docs/PART2.MD` - When designing queries
- `docs/DATASETS.MD` - For GTFS schema reference
- `article/SIGMOD.MD` - For problematic patterns
- `CONSIGNES.MD` - For assignment requirements

### Article Reading Strategy
- SIGMOD.MD already synthesized (see `docs/PART2.MD`)
- Read other articles only when implementing specific Cypher 25 features
- Don't re-read full articles unnecessarily (save tokens)

## Next Action
✅ Neo4j setup complete
🚧 PostgreSQL setup next

## Report Requirements (French)
Must include:
1. Data import strategy
2. Data cleaning process
3. Modeling decisions (reference course material)
4. Constraints and indexes
5. Execution plans with analysis
6. Query comparisons (all 6 mandatory)
7. Performance analysis
8. Explanations (reference SIGMOD lessons)

## Technology Stack
- **PostgreSQL**: Relational database
- **Neo4j**: Graph database (Cypher 5 & 25)
- **Neo4j GDS**: Graph Data Science library
- **Optional**: Memgraph, DuckDB (SQL PGQ)
