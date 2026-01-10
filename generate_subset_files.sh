#!/bin/bash
# Génère des fichiers GTFS réduits pour des lignes de métro spécifiques
# Utilisation : METRO_LINES="3 7 14" ./generate_subset_files.sh

set -e

METRO_LINES=${METRO_LINES:-"3 7 14 11"}

echo "Génération des subsets pour les lignes de métro : $METRO_LINES"

head -1 export/stop_times.csv > export/stop_times_subset.csv
head -1 export/trips.csv > export/trips_subset.csv

echo "Étape 1 : Recherche des routes"
awk -F, -v lines="$METRO_LINES" '
BEGIN { split(lines, keep, " "); }
NR > 1 {
    gsub(/"/, "", $3); gsub(/"/, "", $4);
    line = ($3 != "") ? $3 : $4;
    if ($5 == "1") {
        for (i in keep) {
            if (line == keep[i]) { print $1; break; }
        }
    }
}
' export/routes.csv > /tmp/route_ids.txt

echo "  -> $(wc -l < /tmp/route_ids.txt) routes trouvées"

echo "Étape 2 : Extraction des trajets"
awk -F, '
NR==FNR { routes[$1]=1; next }
FNR==1 { next }
($1 in routes) { print >> "export/trips_subset.csv"; print $3 }
' /tmp/route_ids.txt export/trips.csv > /tmp/trip_ids.txt

echo "  -> $(wc -l < /tmp/trip_ids.txt) trajets trouvés"

echo "Étape 3 : Filtrage de stop_times"
awk -F, '
NR==FNR { trips[$1]=1; next }
($1 in trips) { print }
' /tmp/trip_ids.txt export/stop_times.csv >> export/stop_times_subset.csv

echo ""
echo "Terminé !"

# Nettoyage
rm /tmp/route_ids.txt /tmp/trip_ids.txt
