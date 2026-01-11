# Guide de Démarrage Rapide

## 📋 Checklist de Mise en Route

### 1. Vérifier les Données
```bash
# Depuis la racine du projet
ls -lh import/
# Devrait afficher:
# - airlines.csv (359 bytes, 14 compagnies)
# - airports_projet.csv (~23 KB, 313 aéroports)
# - flights_projet.csv (~6.5 MB, 107,230 vols)
```

### 2. Préparer Neo4j

#### Option A : Neo4j Desktop (Recommandé pour développement)
1. Télécharger Neo4j Desktop : https://neo4j.com/download/
2. Créer une nouvelle base de données
3. Démarrer la base de données
4. Copier les fichiers CSV dans le répertoire d'import :
   ```bash
   # Trouver le chemin d'import
   # Dans Neo4j Browser, exécuter:
   CALL dbms.listConfig() YIELD name, value
   WHERE name = 'dbms.directories.import'
   RETURN value;

   # Puis copier les fichiers
   cp import/*.csv <chemin_retourné>/
   ```

#### Option B : Neo4j Community Edition (Docker)
```bash
docker run \
    --name neo4j-flights \
    -p 7474:7474 -p 7687:7687 \
    -v $(pwd)/import:/var/lib/neo4j/import \
    -e NEO4J_AUTH=neo4j/your_password \
    -e NEO4J_dbms_security_allow__csv__import__from__file__urls=true \
    neo4j:latest
```

### 3. Importer les Données

#### Méthode 1 : Via Neo4j Browser (Simple)
1. Ouvrir http://localhost:7474
2. Se connecter (neo4j / your_password)
3. Copier-coller le contenu de `import_neo4j.cypher` section par section
4. Vérifier après chaque section

#### Méthode 2 : Via Python (Automatisé)
```bash
# Installer le driver Neo4j
pip install neo4j

# Modifier le mot de passe dans le script
nano scripts/import_to_neo4j.py
# Changer: NEO4J_PASSWORD = "your_password"
```

### 4. Préparer PostgreSQL (Optionnel - pour comparaisons SQL)

```bash
# 1. Créer la base de données
createdb flights_db

# 2. Exécuter le script d'import (tables + données + index)
psql -U user -d flights_db -f import_postgresql.sql

# Lancer l'import
cd scripts
python import_to_neo4j.py
```

### 4. Valider l'Import

Exécuter dans Neo4j Browser :
```cypher
// Statistiques rapides
MATCH (a:Airport) RETURN count(a) as airports
UNION
MATCH (al:Airline) RETURN count(al) as airlines
UNION
MATCH ()-[f:FLIGHT]->() RETURN count(f) as flights;

// Résultats attendus:
// - 313 airports
// - 14 airlines
// - 107,230 flights
```

### 5. Explorer les Données

Utiliser le fichier de validation :
```bash
# Dans Neo4j Browser, exécuter les requêtes de:
queries/00_validation.cypher
```

## 🎯 Prochaines Étapes

### Phase 1 : Exploration
- ✅ Données importées
- 🔄 Exécuter les requêtes de validation
- 🔄 Identifier les hubs principaux
- 🔄 Analyser la distribution des retards

### Phase 2 : Requêtes Cypher 5 vs 25
Créer les 6 comparaisons obligatoires :

1. **Increasing property paths**
   ```cypher
   // Cypher 5 : NOT EXISTS
   // Cypher 25 : allReduce
   ```

2. **Quantified graph patterns**
   ```cypher
   // Cypher 25 uniquement
   // Exemple : chemins avec au moins 2 escales
   ```

3. **Shortest path algorithms**
   ```cypher
   // Cypher 5 : shortestPath()
   // Cypher 25 : SHORTEST
   // GDS : gds.shortestPath.*
   ```

4. **GDS algorithms en Cypher 25**
   ```cypher
   // PageRank, betweenness, etc.
   ```

5. **Comparaisons SQL**
   ```sql
   -- WITH RECURSIVE pour chemins
   -- VS Cypher patterns
   ```

6. **Execution plans**
   ```cypher
   PROFILE <query>
   // Analyser BFS unidirectionnel vs bidirectionnel
   ```

### Phase 3 : Rapport

Structure recommandée :

```markdown
# 1. Introduction
- Contexte : comparaison Cypher 5 vs 25
- Dataset : vols US 2015

# 2. Modélisation
- Choix du modèle de graphe
- Justification (vs relationnel)

# 3. Import et Nettoyage
- Process de normalisation
- Gestion des timestamps overnight
- Contraintes et index

# 4. Requêtes et Comparaisons
Pour chaque comparaison :
- Requête Cypher 5
- Requête Cypher 25
- Execution plan (PROFILE)
- Analyse des performances
- Explication des différences

# 5. Problèmes NP-complets
- Référence à SIGMOD
- Exemples concrets sur nos données
- Solutions Cypher 25

# 6. Conclusions
```

## 🔍 Exemples de Requêtes Intéressantes

### Trouver les pires retards en cascade
```cypher
// Vol en retard qui force une correspondance impossible
MATCH (a1:Airport)-[f1:FLIGHT]->(hub:Airport)-[f2:FLIGHT]->(a3:Airport)
WHERE f2.departure_ts < f1.arrival_ts + duration({minutes: 30})
  AND f1.delay > 0
RETURN a1.iata_code, hub.iata_code, a3.iata_code,
       f1.delay as initial_delay,
       duration.between(f1.arrival_ts, f2.departure_ts).minutes as connection_time
ORDER BY f1.delay DESC
LIMIT 10;
```

### Hubs avec le plus de connexions directes
```cypher
MATCH (hub:Airport)
MATCH (hub)-[:FLIGHT]->(dest:Airport)
WITH hub, count(DISTINCT dest) as destinations
RETURN hub.iata_code, hub.city, destinations
ORDER BY destinations DESC
LIMIT 10;
```

### Chemins avec contrainte de temps (Cypher 25)
```cypher
// Trouver tous les chemins LAX -> JFK avec max 1 escale
// et temps de correspondance >= 30 min
MATCH path = (lax:Airport {iata_code: 'LAX'})
  -[:FLIGHT*1..2]->(jfk:Airport {iata_code: 'JFK'})
WHERE allReduce(valid = true, i IN range(0, size(relationships(path))-2) |
  valid AND
  relationships(path)[i].arrival_ts + duration({minutes: 30})
    <= relationships(path)[i+1].departure_ts
)
RETURN path
LIMIT 10;
```

## 📚 Ressources

- **Documentation Neo4j** : https://neo4j.com/docs/
- **Cypher 25 Guide** : `article/SOLVE_HARD_GRAPH_PROBLEMS_WITH_CYPHER_25.MD`
- **SIGMOD Analysis** : `article/SIGMOD.MD`
- **Consignes du projet** : `CONSIGNES.MD`

## 🆘 Troubleshooting Rapide

**Erreur : "File not found"**
→ Vérifier que les CSV sont dans le répertoire d'import Neo4j

**Import très lent**
→ Augmenter la heap size dans neo4j.conf
→ Utiliser des batches plus petits (500 au lieu de 1000)

**Contrainte violation**
→ Supprimer les contraintes existantes puis réimporter

**Pas de résultats dans les requêtes**
→ Vérifier les labels (case-sensitive) : `:Airport` pas `:airport`
