## Pre-requisites
In order to run `get-addresses.py`, you will need: 
  - python3.6+
  -  a mapbox token 
  -  a csv file of latitude/longitude coordinate pairs that need geocoding

example_file.csv:
```
1,47.20628052473762,-122.5369473400126
2,44.67283305354945,-110.79387527825949
3,31.788443665770124,-93.32883496460246
```
(It can have more columns, it just needs an id, latitude, & longitude

1) Get your local python environment ready by running:
`python -m pip install -r requirements.txt`
2) Then get your python file ready by changing lines that I've commented, with your own specific data. I've commented lines in the `get-addresses.py` file with changes you will need to make in order to run. You may also want to change the api call itself
3) Once you have changes in place, you can just run `python get-addresses.py`. It will perform the following:

  - Print the first result of each api call in your terminal
  - Cache results to spatialite-cache.sql (this just means that if api calls are interrupted you can re-run the python script and it will basically pick up where it left off without starting queries over
  - update your input csv with placenames

