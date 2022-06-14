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

# YOU CAN IGNORE THESE LINES, DELETE THEM FROM YOUR RUN
config = configparser.ConfigParser()
# YOU CAN IGNORE THESE LINES, DELETE THEM FROM YOUR RUN
config.read("config.ini")

file = 'sample.csv'

data = pd.read_csv(file)  # LOAD DATA WITH X, Y values
MAPBOX_ACCESS_TOKEN = config["MAPBOX"]["ACCESS_TOKEN"]
# YOU CAN REPLACE AS:
# MAPBOX_ACCESS_TOKEN = "your-token-here"

places = []
requests_cache.install_cache("spatial-cache")

max_attempts = 10
attempts = 0

while attempts < max_attempts:
    for index, row in data.iterrows():
        # YOU WILL NEED TO REPLACE THE VALUE IN STRING QUOTATIONS WITH YOUR LONGITUDE COLUMN
        lon = row["lon"]
        # YOU WILL NEED TO REPLACE THE VALUE IN STRING QUOTATIONS WITH YOUR LATITUDE COLUMN
        lat = row["lat"]
        ID = row["id"]  # YOUR ID COLUMN
        r = requests.get(
            "https://api.mapbox.com/geocoding/v5/mapbox.places/{},{}.json?types=country,region,place&access_token={}".format(
                lon, lat, MAPBOX_ACCESS_TOKEN
            )
        )
        response = r.json()

        if response["features"] == []:
            place_name = "Null"
        if response["features"] != []:
            place_name = response["features"][0]["place_name"]
            place = place_name.split(",")[0]
            print(lat, lon, place)
            places.append((lat, lon, place))  # your column id
        # stop once we've done all features without an address
        # unless we hit a rate-limit
    if r.status_code != 429:
        break
    # If rate limited, wait and try again
    time.sleep((2**attempts) + random.random())
    attempts = attempts + 1

output_df = pd.DataFrame(places, columns=['lat', 'lon', 'place'])
# CHANGE NAME OF OUTPUT FILE IF DESIRED
output_df.to_csv('sample_output.csv', index=None)
