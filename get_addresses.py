#!/usr/bin/env python3
import configparser
import json
import os
import random
import time

import geopandas as gpd
import pandas as pd
import requests
import requests_cache
from mapbox import Geocoder
from sqlalchemy import create_engine

config = configparser.ConfigParser()
config.read("config.ini")

file = os.path.join(
    "data",
    "bigquery-public-data--geo-openstreetmap--bars/bigquery-public-data-geo-openstreetmap-bars-point.shp",
)

data = gpd.read_file(file, crs=4326)
MAPBOX_ACCESS_TOKEN = config["MAPBOX"]["ACCESS_TOKEN"]

places = []
requests_cache.install_cache("spatial-cache")

max_attempts = 10
attempts = 0

while attempts < max_attempts:
    for index, row in data.iterrows():
        # get addresses only for OSM features that do not have addresses
        if row["address"] == None:
            lon = row["geometry"].x
            lat = row["geometry"].y
            osm_id = row["osm_id"]  # keep id column to compare to original table
            r = requests.get(
                "https://api.mapbox.com/geocoding/v5/mapbox.places/{},{}.json?types=country,region,address&access_token={}".format(
                    lon, lat, MAPBOX_ACCESS_TOKEN
                )
            )
            response = r.json()
            if response["features"] == []:
                place_name = "Null"
            if response["features"] != []:
                place_name = response["features"][0]["place_name"]
                address = place_name.split(",")[0]
                print(lat, lon, address)
                places.append((lat, lon, address, osm_id))
        if row["address"] != None:
            pass
    # stop once we've done all features without an address
    # unless we hit a rate-limit
    if r.status_code != 429:
        break
        # If rate limited, wait and try again
    time.sleep((2**attempts) + random.random())
    attempts = attempts + 1

# if there are new addresses, send them to PostgreSQL
if len(places) > 0:
    cols = ["lat", "lon", "address", "osm_id"]
    query_result = pd.DataFrame(places, columns=cols)
    engine = create_engine("postgresql://postgres:postgres@localhost:5432/iggy_data")
    query_result.to_sql("get_addresses", engine, if_exists="replace")
