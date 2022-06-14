#!/usr/bin/env python3
import configparser
import json
import os
import random
import time

import pandas as pd
import requests
import requests_cache
from mapbox import Geocoder

config = configparser.ConfigParser() ## YOU CAN IGNORE THESE LINES, DELETE THEM FROM YOUR RUN
config.read("config.ini") ## YOU CAN IGNORE THESE LINES, DELETE THEM FROM YOUR RUN

file = 'sample.csv'

data = pd.read_file(file, crs=4326) # LOAD DATA WITH X, Y values
MAPBOX_ACCESS_TOKEN = config["MAPBOX"]["ACCESS_TOKEN"]
# YOU CAN REPLACE AS: 
    # MAPBOX_ACCESS_TOKEN = "your token here"

places = []
requests_cache.install_cache("spatial-cache")

max_attempts = 10
attempts = 0

while attempts < max_attempts:
    for index, row in data.iterrows():
        lon = row["geometry_x"] # YOU WILL NEED TO REPLACE WITH YOUR LONGITUDE COLUMN
        lat = row["geometry_y"] # YOU WILL NEED TO REPLACE WITH YOUR LATITUDE COLUMN
        ID = row ["id"] # YOUR ID COLUMN
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
            places.append((lat, lon, id)) # your column id
        # stop once we've done all features without an address
        # unless we hit a rate-limit
        if r.status_code != 429:
            break
        # If rate limited, wait and try again
        time.sleep((2**attempts) + random.random())
        attempts = attempts + 1
