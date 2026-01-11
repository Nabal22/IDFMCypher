# Instructions d'Import Neo4j

## Préparation

### 1. Placer les fichiers CSV dans le répertoire d'import Neo4j

Neo4j nécessite que les fichiers CSV soient dans son répertoire d'import. Localisez ce répertoire :

```bash
# Vérifier la configuration Neo4j
# Le répertoire d'import est défini dans neo4j.conf
# Par défaut : /var/lib/neo4j/import (Linux) ou ~/Library/Application Support/Neo4j Desktop/Application/relate-data/dbmss/dbms-xxx/import (Mac)
```

**Copier les fichiers CSV :**
```bash
# Exemple pour Neo4j Desktop sur Mac
cp import/*.csv ~/Library/Application\ Support/com.Neo4j.Relate/Data/dbmss/dbms-*/import/

# Ou utiliser la commande Neo4j pour trouver le chemin
neo4j-admin dbms set-initial-password neo4j
```

**Vérifier les permissions :**
```bash
chmod 644 import/*.csv
```

### 2. Configuration Neo4j

Assurez-vous que Neo4j autorise l'import de fichiers locaux dans `neo4j.conf` :

```conf
# Uncomment to allow CSV import from file:/// URIs
dbms.security.allow_csv_import_from_file_urls=true
```

## Méthodes d'Import

### Méthode 1 : Via Neo4j Browser (Recommandé pour démarrer)

1. Ouvrez Neo4j Browser : http://localhost:7474
2. Connectez-vous avec vos identifiants
3. Exécutez le script `import_neo4j.cypher` section par section :
   - Copiez chaque section dans le browser
   - Exécutez et vérifiez les résultats
   - Passez à la section suivante

**Avantages :**
- Contrôle visuel de chaque étape
- Facile à déboguer
- Voir les résultats intermédiaires

### Méthode 2 : Via cypher-shell (Pour import complet)

```bash
# Se connecter à Neo4j
cypher-shell -u neo4j -p your_password

# Exécuter le script
:source import_neo4j.cypher
```

### Méthode 3 : Via neo4j-admin (Pour import initial massif)

Pour un import initial très rapide sans index, utilisez `neo4j-admin import` :

```bash
# Arrêter Neo4j
neo4j stop

# Import avec neo4j-admin (beaucoup plus rapide pour grands volumes)
neo4j-admin database import full \
  --nodes=Airport=import/airports_projet.csv \
  --nodes=Airline=import/airlines.csv \
  --relationships=FLIGHT=import/flights_projet.csv \
  neo4j

# Redémarrer Neo4j
neo4j start
```

**Note :** Cette méthode nécessite un format CSV spécifique avec headers de type.

## Résultats Attendus

Après l'import, vous devriez avoir :

- **313 nœuds** `Airport`
- **14 nœuds** `Airline`
- **~107,230 relations** `FLIGHT`

### Vérification rapide

```cypher
// Statistiques générales
MATCH (a:Airport) RETURN count(a) as airports
UNION
MATCH (al:Airline) RETURN count(al) as airlines
UNION
MATCH ()-[f:FLIGHT]->() RETURN count(f) as flights;

// Vérifier la structure du graphe
CALL db.schema.visualization();

// Top 5 des hubs (aéroports les plus connectés)
MATCH (a:Airport)-[f:FLIGHT]->()
RETURN a.iata_code, a.city, count(f) as departures
ORDER BY departures DESC
LIMIT 5;
```

## Troubleshooting

### Erreur : "Couldn't load the external resource"

**Solution :** Vérifiez que les fichiers CSV sont dans le bon répertoire d'import Neo4j.

```cypher
// Test pour trouver le répertoire d'import
CALL dbms.listConfig() YIELD name, value
WHERE name = 'dbms.directories.import'
RETURN value;
```

### Erreur : "CSV file not found"

**Solutions :**
1. Vérifiez les permissions des fichiers CSV
2. Utilisez des chemins absolus : `file:///absolute/path/to/file.csv`
3. Sur Windows, utilisez : `file:///C:/path/to/file.csv`

### Performance lente

**Solutions :**
1. Augmentez la mémoire heap de Neo4j dans `neo4j.conf` :
   ```conf
   dbms.memory.heap.initial_size=2g
   dbms.memory.heap.max_size=4g
   ```
2. Utilisez des batches plus petits (500 rows au lieu de 1000)
3. Créez les index APRÈS l'import des données

### Contraintes déjà existantes

```cypher
// Supprimer toutes les contraintes
CALL db.constraints() YIELD name
CALL db.dropConstraint(name) YIELD name as dropped
RETURN dropped;

// Supprimer tous les index
CALL db.indexes() YIELD name
CALL db.dropIndex(name) YIELD name as dropped
RETURN dropped;
```

## Modèle de Données

```
(:Airport {iata_code, name, city, state, country, latitude, longitude})
(:Airline {iata_code, name})

(:Airport)-[:FLIGHT {
  airline,
  airline_name,
  departure_ts,  // datetime
  arrival_ts,    // datetime
  distance,      // integer (miles)
  delay          // float (minutes, can be negative)
}]->(:Airport)
```

## Prochaines Étapes

1. ✅ Import des données
2. 🔄 Créer des requêtes Cypher 5
3. 🔄 Créer des requêtes Cypher 25 équivalentes
4. 🔄 Comparer les performances
5. 🔄 Analyser les plans d'exécution
6. 🔄 Rédiger le rapport
