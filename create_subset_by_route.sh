#!/bin/bash

echo "🚀 Démarrage du filtrage optimisé..."

# Fichiers
INPUT_ROUTES="export/routes.csv"
INPUT_TRIPS="export/trips.csv"
INPUT_STOP_TIMES="export/stop_times.csv"
OUTPUT="export/stop_times_subset.csv"
OUTPUT_TRIPS="export/trips_subset.csv"
# Lignes de métro à garder (espace séparé). Exemple : "11" ou "3 7 14 11"
METRO_LINES=${METRO_LINES:-"3 7 14 11"}
TEMP_ROUTES="/tmp/route_ids.txt"
TEMP_TRIPS="/tmp/trip_ids.txt"

# Assurer l'existence des dossiers temporaires
mkdir -p "$(dirname "$TEMP_ROUTES")" "$(dirname "$TEMP_TRIPS")"

# 1. Créer le header
head -1 "$INPUT_STOP_TIMES" > "$OUTPUT"
head -1 "$INPUT_TRIPS" > "$OUTPUT_TRIPS"

# 2. Extraire les route_ids 
echo "📍 Étape 1: Extraction des route_ids "
awk -F, -v lines="$METRO_LINES" '
BEGIN {
    split(lines, keep, " ");
}
NR > 1 {
    short_name = $3; long_name = $4; route_type = $5;
    gsub(/"/, "", short_name);
    gsub(/"/, "", long_name);
    line = (short_name != "") ? short_name : long_name;
    if (route_type == "1" && (line in keep)) {
        print $1
    }
}
' "$INPUT_ROUTES" > "$TEMP_ROUTES"

echo "   -> $(wc -l < \"$TEMP_ROUTES\") lignes trouvées."

# Vérification de sécurité
if [ ! -s "$TEMP_ROUTES" ]; then echo "❌ Erreur: Aucune route trouvée."; exit 1; fi

# 3. Extraire les trip_ids (Méthode awk rapide)
echo "🚌 Étape 2: Extraction des trip_ids..."
awk -F, -v trips_subset="$OUTPUT_TRIPS" '
    # FNR==NR : Lecture du premier fichier (route_ids)
    FNR==NR { routes[$1]=1; next }
    
    # Ignorer le header du second fichier (Attention: pas d apostrophe ici !)
    FNR==1 { next }
    
    # Lecture du second fichier (trips.csv)
    # Si la colonne 1 (route_id) est dans notre liste
    ($1 in routes) {
        print $0 >> trips_subset;
        print $3;
    }
' "$TEMP_ROUTES" "$INPUT_TRIPS" > "$TEMP_TRIPS"

echo "   -> $(wc -l < \"$TEMP_TRIPS\") trajets trouvés (écrits dans $OUTPUT_TRIPS)."

# Vérification de sécurité
if [ ! -s "$TEMP_TRIPS" ]; then echo "❌ Erreur: Aucun trajet trouvé."; exit 1; fi

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
' "$TEMP_TRIPS" "$INPUT_STOP_TIMES" >> "$OUTPUT"

# Statistiques finales
echo ""
echo "✅ Terminé !"
echo "📊 Lignes conservées : $(wc -l < \"$OUTPUT\")"
ls -lh "$OUTPUT"

# Nettoyage
rm "$TEMP_ROUTES" "$TEMP_TRIPS"