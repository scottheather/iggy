#!/bin/bash

# Using a bash script to call ogr2ogr, sql, and python scripts
PSQL = "psql -h localhost -U postgres"

echo "DROP DATABASE IF EXISTS iggy_data;" | $PSQL
echo "CREATE DATABASE iggy_data" | $PSQL
echo "CREATE EXTENSION IF NOT EXISTS postgis;" | $PSQL

PSQL="psql -h localhost -U postgres -d iggy_data"

ogr2ogr -f "PostgreSQL" PG:"host=localhost user=postgres dbname=iggy_data password=postgres" /
 drive-download-20220314T220624Z-001/ms-bldg-footprints--dc.geojson -nln building_footprints /
 -nlt PROMOTE_TO_MULTI -t_srs epsg:3857 -overwrite

ogr2ogr -f "PostgreSQL" PG:"host=localhost user=postgres dbname=iggy_data password=postgres" data/bigquery-public-data--geo-openstreetmap--bars/bigquery-public-data-geo-openstreetmap-bars-point.shp -nln osm_bars -t_srs epsg:3857 -overwrite

# add DC OCTO data
ogr2ogr -f "PostgreSQL" PG:"host=localhost user=postgres dbname=iggy_data password=postgres" /
data/Certificate_of_Occupancy.geojson -nln certificate_occupancy -nlt PROMOTE_TO_MULTI / 
-t_srs epsg:3857 -overwrite

ogr2ogr -f "PostgreSQL" PG:"host=localhost user=postgres dbname=iggy_data password=postgres" /
data/Liquor_Licenses.geojson -nln liquor_licenses -nlt PROMOTE_TO_MULTI -t_srs epsg:3857 -overwrite

python get_addresses.py

# run SQL to processs datasets
# calculate square footage and occupancy
$PSQL < process_data.sql

python app.py