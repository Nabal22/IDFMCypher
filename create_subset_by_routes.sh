#!/bin/bash

# Script pour créer un subset de stop_times.csv basé sur des routes spécifiques
# Extrait les données pour certaines lignes de métro/RER

echo "Création de stop_times_subset.csv..."
echo "Extraction des lignes: Metro 3, 7, 14"

# Créer le header
head -1 export/stop_times.csv > export/stop_times_subset.csv

# Obtenir les route_ids pour les lignes 3, 7, et 14
echo "Étape 1: Extraction des route_ids..."
grep -E '"3"|"7"|"14"' export/routes.csv | cut -d',' -f1 > /tmp/route_ids.txt

echo "Routes trouvées:"
cat /tmp/route_ids.txt

# Obtenir les trip_ids pour ces routes
echo ""
echo "Étape 2: Extraction des trip_ids..."
grep -F -f /tmp/route_ids.txt export/trips.csv | cut -d',' -f3 > /tmp/trip_ids.txt

echo "Nombre de trips: $(wc -l < /tmp/trip_ids.txt)"

# Extraire les stop_times pour ces trips (limité à 50000 lignes pour la performance)
echo ""
echo "Étape 3: Extraction des stop_times (max 50000 lignes)..."
grep -F -f /tmp/trip_ids.txt export/stop_times.csv | head -50000 >> export/stop_times_subset.csv

# Statistiques
echo ""
echo "Terminé!"
echo ""
echo "Statistiques:"
wc -l export/stop_times_subset.csv
ls -lh export/stop_times_subset.csv

echo ""
echo "Comparaison:"
echo "Original: $(wc -l < export/stop_times.csv) lignes (796 MB)"
echo "Subset:   $(wc -l < export/stop_times_subset.csv) lignes"

# Nettoyage
rm /tmp/route_ids.txt /tmp/trip_ids.txt 2>/dev/null

echo ""
echo "Fichier créé: export/stop_times_subset.csv"
