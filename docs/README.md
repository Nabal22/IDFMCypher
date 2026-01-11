# Documentation du Projet Cypher 5 vs 25

Ce dossier contient toute la documentation du projet.

## 📖 Guide de Lecture Recommandé

### 🚀 Pour Démarrer
1. **[QUICKSTART.md](QUICKSTART.md)** - Commencez ici !
   - Setup rapide de Neo4j et PostgreSQL
   - Import des données
   - Premières requêtes
   - Top 5 hubs et statistiques

### 📊 Pour Exécuter les Requêtes
2. **[QUERIES_GUIDE.md](QUERIES_GUIDE.md)** - Guide complet
   - Comment exécuter chaque comparaison
   - Analyses à faire pour le rapport
   - Troubleshooting
   - Checklist avant de rendre

### 📈 État du Projet
3. **[PROJET_COMPLETED.md](PROJET_COMPLETED.md)** - Progression
   - Ce qui est fait (70%)
   - Ce qui reste à faire
   - Métriques et statistiques
   - Prochaines étapes détaillées

## 🗄️ Configuration des Bases de Données

## 📐 Modèle de Données

6. **[DATA_MODEL.md](DATA_MODEL.md)**
   - Schéma du graphe (diagramme)
   - Propriétés des nœuds et relations
   - Patterns de requêtes courants
   - Considérations de performance
   - Évolutions possibles

## 🎯 Par Objectif

### Je veux juste commencer rapidement
→ **[QUICKSTART.md](QUICKSTART.md)**

### Je dois exécuter les requêtes pour le rapport
→ **[QUERIES_GUIDE.md](QUERIES_GUIDE.md)**

### Je veux comprendre le modèle de données
→ **[DATA_MODEL.md](DATA_MODEL.md)**

### Je veux voir ce qui a été fait
→ **[PROJET_COMPLETED.md](PROJET_COMPLETED.md)**

## 📏 Taille des Fichiers

| Fichier | Taille | Contenu |
|---------|--------|---------|
| QUICKSTART.md | 5.6 KB | Guide rapide |
| QUERIES_GUIDE.md | 9.9 KB | Guide d'exécution complet |
| DATA_MODEL.md | 8.9 KB | Modèle détaillé |
| PROJET_COMPLETED.md | 11 KB | État d'avancement |
| **Total** | **56.7 KB** | **7 fichiers** |

## 🔗 Liens Utiles

### Fichiers Principaux du Projet
- **README principal** : `../README.md`
- **Consignes** : `../CONSIGNES.MD`
- **Rapport** : `../RAPPORT.md` (à rédiger)

### Scripts
- **Import PostgreSQL** : `../import_postgresql.sql`
- **Import Neo4j** : `../import_neo4j.cypher`
- **Python import** : `../scripts/import_to_*.py`

### Requêtes
- **Validation** : `../queries/00_validation.*`
- **Comparaison 1** : `../queries/01_increasing_property_paths.*`
- **Comparaison 2** : `../queries/02_quantified_graph_patterns.*`
- **Comparaison 3** : `../queries/03_shortest_path_algorithms.*`
- **Comparaison 4** : `../queries/04_gds_algorithms_in_cypher25.cypher`

### Articles de Référence
- **SIGMOD** : `../article/SIGMOD.MD`
- **Cypher 25** : `../article/SOLVE_HARD_GRAPH_PROBLEMS_WITH_CYPHER_25.MD`
- **Query Chomp Repeat** : `../article/QUERY_CHOMP_REPEAT.MD`

## 🎓 Pour le Rapport

Les fichiers les plus importants pour rédiger le rapport :

1. **[QUERIES_GUIDE.md](QUERIES_GUIDE.md)** - Structure des analyses
2. **[DATA_MODEL.md](DATA_MODEL.md)** - Schéma et justifications
3. **[PROJET_COMPLETED.md](PROJET_COMPLETED.md)** - Points clés SIGMOD
4. **[POSTGRESQL_INSTRUCTIONS.md](POSTGRESQL_INSTRUCTIONS.md)** - Comparaison SQL

Tous les fichiers de requêtes contiennent une section finale :
```
// POINTS CLÉS POUR LE RAPPORT
```

Utilisez ces sections pour structurer votre rapport !

---

**Dernière mise à jour** : Janvier 2026
**Statut du projet** : 70% complété
