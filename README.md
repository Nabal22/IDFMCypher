# IDFM Cypher 5 vs 25 Comparison Project

Projet Master comparant Cypher 5 et Cypher 25 sur des données de transport IDFM (GTFS).

## Quick Start

### 1. Generate Dataset Subsets
```bash
./generate_subset_files.sh
```
Génère `trips_subset.csv` et `stop_times_subset.csv` (lignes 3, 7, 14, 11).

### 2. Setup Neo4j
```bash
# Copy CSV files to Neo4j import folder
# Then in Neo4j Browser, run:
# (see neo4j-import.cypher for full script)
```

### 3. Setup PostgreSQL
```bash
psql -d postgres -f postgres-full-setup.sql
```

## Project Structure

```
├── generate_subset_files.sh    # Generate GTFS subsets
├── neo4j-import.cypher          # Neo4j import script
├── postgres-full-setup.sql      # PostgreSQL complete setup
├── test-queries.md              # Validation queries
├── docs/
│   ├── PART1.MD                 # Import guide
│   ├── PART2.MD                 # Query comparisons
│   └── DATASETS.MD              # GTFS reference
├── queries/                     # All query implementations
│   ├── README.md                # Query documentation
│   ├── 01_increasing_paths.*    # Cypher 5/25 + SQL
│   ├── 02_quantified_patterns.* # Cypher 5/25 + SQL
│   ├── 03_shortest_path.*       # Cypher 5/25 + SQL
│   ├── 04_shortest_path_gds.*   # Neo4j GDS algorithms
│   └── 05_additional_patterns.* # Subset sum, trails, etc.
└── export/
    ├── *_subset.csv             # Generated subsets
    └── *.csv                    # Original GTFS files
```

## Documentation

- **CLAUDE.MD** - Project overview and status
- **CONSIGNES.MD** - Assignment requirements (French)
- **docs/** - Detailed guides for each phase

## Requirements

- Neo4j Desktop 5.x (Cypher 25 support)
- PostgreSQL 14+
- GTFS data in `export/` folder

## Status

- ✅ Part 1: Data import complete
- ✅ Part 2: Query development complete (9 query files)
- 🚧 Part 3: Testing, analysis and report (next)

## Key Scripts

| Script | Purpose |
|--------|---------|
| `generate_subset_files.sh` | Create coherent GTFS subsets |
| `neo4j-import.cypher` | Import data into Neo4j |
| `postgres-full-setup.sql` | Full PostgreSQL setup |
| `test-queries.md` | Validation queries for both DBs |
