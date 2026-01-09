#!/bin/bash

# Script pour créer un subset de stop_times.csv
# Prend les 100 000 premières lignes (+ header)

echo "Création de stop_times_mini.csv"

head -100001 export/stop_times.csv > export/stop_times_mini.csv

echo "Terminé"
