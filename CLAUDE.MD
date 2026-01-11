# Project Context for Claude Code

## Project Overview
Master's level database project comparing Cypher 5 and Cypher 25 query languages using US flight data from 2015.

## Project Structure

```
IDFMCypher/
├── source/           # Raw datasets (Kaggle Flight Delays 2015)
│   ├── flights.csv   # Full dataset (5M+ rows)
│   ├── airports.csv  # US airports (323 airports)
│   └── airlines.csv  # Airlines (14 airlines)
├── scripts/          # Data preprocessing
│   └── normalize_data.py  # Filters to first week of Jan 2015
├── import/           # Cleaned datasets for Neo4j/PostgreSQL
│   ├── flights_projet.csv   # ~107k flights (Jan 1-7, 2015)
│   ├── airports_projet.csv  # 313 used airports
│   └── airlines.csv         # 14 airlines
├── queries/          # Cypher and SQL queries
├── article/          # Research articles (SIGMOD, Cypher 25)
├── CONSIGNES.MD      # Assignment requirements
├── RAPPORT.md        # Project report
└── CLAUDE.MD         # This file
```

## Current Status (Branch: flip-reset)
- **Dataset**: Switched from IDFM transport to Kaggle Flight Delays 2015
- **Data processed**: 107,230 flights from first week of January 2015
- **Scope**: US domestic flights across 313 airports, 14 airlines
- **PostgreSQL**: ✅ Database created and populated (flights_db)
- **Neo4j**: 🔄 Ready for import
- **Next**: Create and compare Cypher 5 vs Cypher 25 queries

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
- **Source**: Kaggle "2015 Flight Delays and Cancellations" (US DOT)
- **Period**: January 1-7, 2015 (first week only for manageable size)
- **Scale**: 107,230 flights across 313 airports, 14 airlines
- **Graph structure**: Perfect for path algorithms (multi-hop flights, connections)
- **Edge properties**:
  - `distance`: Flight distance in miles
  - `delay`: Departure delay in minutes (can be negative)
  - `departure_ts`: ISO timestamp (e.g., "2015-01-01T23:54:00")
  - `arrival_ts`: ISO timestamp with overnight handling
- **Node properties** (airports):
  - `IATA_CODE`: 3-letter code (e.g., "LAX")
  - Geographic: LATITUDE, LONGITUDE, CITY, STATE, COUNTRY
- **Data cleaning** (scripts/normalize_data.py):
  - Filters to first week of January 2015
  - Handles midnight crossover (2400 → 0000)
  - Computes overnight flights (arrival next day)
  - Drops rows with missing times
  - Filters airports to only those used in flights

## When Working With Claude

### I Should Prioritize
1. **Part 1 before Part 2** - Cannot query without data
2. **Use processed data** - import/ folder has cleaned CSVs ready for Neo4j
3. **Document decisions** - Modeling choices for report
4. **Reference SIGMOD** - Explain why patterns fail
5. **Execution plans** - Show algorithmic differences

### Graph Modeling Considerations
- **Natural graph**: Airports = nodes, Flights = relationships
- **Multi-hop paths**: Represent connecting flights (with time constraints)
- **Properties on edges**: Distance, delay, timestamps enable rich queries
- **Potential queries**:
  - Shortest path by distance vs by number of hops
  - Paths with constraints (max delay, time windows)
  - Connected components (airport reachability)
  - Hub detection (airports with most connections)
  - Delay propagation patterns

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
