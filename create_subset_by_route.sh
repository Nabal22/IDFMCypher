#!/bin/bash

echo "🚀 Démarrage du filtrage optimisé..."

# Fichiers
INPUT_ROUTES="export/routes.csv"
INPUT_TRIPS="export/trips.csv"
INPUT_STOP_TIMES="export/stop_times.csv"
OUTPUT="export/stop_times_subset.csv"
TEMP_ROUTES="/tmp/route_ids.txt"
TEMP_TRIPS="/tmp/trip_ids.txt"

# 1. Créer le header
head -1 $INPUT_STOP_TIMES > $OUTPUT

# 2. Extraire les route_ids (Correction colonne 4)
echo "📍 Étape 1: Extraction des route_ids (Métro 3, 7, 14)..."
awk -F, '
NR > 1 {
    # Nettoyage des guillemets éventuels
    gsub(/"/, "", $4); gsub(/"/, "", $5);
    
    # Colonne 4 = Nom de la ligne ("3", "7", "14")
    # Colonne 5 = Type (1 pour Métro)
    if ($5 == "1" && ($4 == "3" || $4 == "7" || $4 == "14")) {
        print $1
    }
}' $INPUT_ROUTES > $TEMP_ROUTES

echo "   -> $(wc -l < $TEMP_ROUTES) lignes trouvées."

# Vérification de sécurité
if [ ! -s $TEMP_ROUTES ]; then echo "❌ Erreur: Aucune route trouvée."; exit 1; fi

# 3. Extraire les trip_ids (Méthode awk rapide)
echo "🚌 Étape 2: Extraction des trip_ids..."
awk -F, '
    # FNR==NR : Lecture du premier fichier (route_ids)
    FNR==NR { routes[$1]=1; next } 
    # Lecture du second fichier (trips.csv)
    # Si la colonne 1 (route_id) est dans notre liste
    ($1 in routes) { print $3 }
' $TEMP_ROUTES $INPUT_TRIPS > $TEMP_TRIPS

echo "   -> $(wc -l < $TEMP_TRIPS) trajets trouvés."

# Vérification de sécurité
if [ ! -s $TEMP_TRIPS ]; then echo "❌ Erreur: Aucun trajet trouvé."; exit 1; fi

# 4. Extraire les stop_times (Méthode awk optimisée pour gros fichiers)
echo "⏱️ Étape 3: Filtrage de stop_times (800 Mo)..."
echo "   Cette étape peut prendre 10-20 secondes, mais ne bloquera pas."

awk -F, '
    # 1. Chargement des trip_ids en RAM (Hash Map)
    FNR==NR { 
        trips[$1]=1; 
        next; 
    } 
    # 2. Lecture du flux stop_times.csv
    # Vérifie si la colonne 1 (trip_id) est dans la Map
    ($1 in trips) { 
        print $0 
    }
' $TEMP_TRIPS $INPUT_STOP_TIMES >> $OUTPUT

# Statistiques finales
echo ""
echo "✅ Terminé !"
echo "📊 Lignes conservées : $(wc -l < $OUTPUT)"
ls -lh $OUTPUT

# Nettoyage
rm $TEMP_ROUTES $TEMP_TRIPS