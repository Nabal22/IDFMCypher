# Project Context for Claude Code

## Project Overview
Master's level database project comparing Cypher 5 and Cypher 25 query languages using ---

## Project Structure

```

```

## 3-Phase Workflow

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
- `article/SIGMOD.MD` - For problematic patterns
- `article/SOLVE_HARD_GRAPH_PROBLEMS_WITH_CYPHER_25.MD`
- `article/QUERY_CHOMP_REPEAT.MD`
- `CONSIGNES.MD` - For assignment requirements

### Article Reading Strategy
- SIGMOD.MD already synthesized
- Read other articles only when implementing specific Cypher 25 features
- Don't re-read full articles unnecessarily (save tokens)

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
