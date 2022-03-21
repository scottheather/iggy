## Iggy Data Engineer Take Home

Assignment:

> Specifically, they’d like a tool that allows them to input a location (latitude/longitude), and returns a list of the 5 nearest bars along with their building square footage (as a proxy for capacity).

--------------------------------------------------------------------------------------------------------
## Set-up/Running

1) Additional Data Files
There are two data files (Certificate of Occupancy & Liquor Licenses) in addition to those supplied. While I wouldn't normally post data to github, for the purposes of widespread sharing, I've uploaded those to my `iggy` repository. If those are somehow lost, they are available at Open Data DC ([Liquor Licenses](https://opendata.dc.gov/datasets/liquor-licenses/explore) and [Certificate of Occupancy](https://opendata.dc.gov/datasets/certificate-of-occupancy/explore)).

2) Locally Hosted
Everything in the container/app is hosted locally, namely the Postgres instance, and the API. The API, however, is not hosted and thus runs locally and will require either a browser or a service like [Postman](https://www.postman.com/downloads/) to view.

3) Set-up Requirements
I was unable to effectively connect my Docker container with the Postgres instance and deploy scripts through bash. After many hours of research, I discovered this was due to a corrupted Postgresql installation. Since this ate-up much of my work time, I decided to "ship" this product with a simple bash script that runs all other processes. As a result, expected dependencies aren't provided. Instead, this work assumes the presence of the following applications:

- PostgreSQL: with a default user 'postgres'
- GDAL/ogr2ogr: (for this use-case, I installed through `brew install gdal`)
- Python (I'm running Python 3.9.10)
- Not necessary, but I recommend running in a python virtual environment: `pip install virtualenv`
- All other python packages are included in `requirements.txt`

3) Running the Build

```
$ python virtualenv venv
$ source venv/bin/activate
$ pip install -r requirements.txt

$ chmod +x run.sh
$ ./run.sh
```

--------------------------------------------------------------------------------------------------------
## Interacting with the API

There are only two routes available in the API, `"/all"` and `"/bars"`. 
  - `"/all"` displays the entire list of provided bars, 
  - `"/bars"` is an endpoint for querying. 
  
  There is only one parameter with which to query: `location`. Location is received in an `X,Y` coordinate format. A sample query:
  
  `http://127.0.0.1:5000/bars?location=-77.037793,38.902134`
  
  A single entry looks like:
```
        "Distance From Location (Meters)": "153.36",
        "Expected Full Occupancy": 229,
        "Liquor License": false,
        "Name": "Off The Record",
        "Square Footage": 5577
```
  
  -------------------------------------------------------------------------------------------------------
  ## Project Review: Thoughts about additional work/updates
  
### 1) Containerizing
As mentioned above, attempting to containerize the project for delivery took the bulk of my time. I started with a Dockerfile and docker-compose.yml, but connecting to the database proved especially difficult when my existing Postgres database had some limiting provisions associated in my `pg_hba.conf` and PG_DATA files. If I'd had more time, I'd work through removing Postgres/all associated files and attempting to let Docker 'drive' those configurations.

### 2) Data Cleaning/Operations
When inspecting the provided data: OSM bar locations in DC, and Building Footprints in DC, I identified several issues that would challenge my analysis:

- **OSM** is a great data source, but many of these bars were closed/potentially relocated during the pandemic. I'd estimate that ~15% of these bars were permanently closed. There were other data issues: about 40 bars did not intersect with a building (either the building was missing, or the bar was misplaced), there were some duplicates, some features that weren't duplicate, but different bar names at the same location, some bars had incorrect names, etc.  I also added a field for "liquor license", in the case that the bar is closed.

- **Building footprints** are useful data, but in DC (and most cities), these cities represent entire buildings instead of individual units. These bars occupy buildings that may contain 6+ units. My first instinct was to find perhaps better data - parcel/etc, but I decided against that route because it isn't scaleable -- if this "client" were to ask for additional locations, re-creating this analysis would be easier with the national Microsoft building footprint dataset. Instead, I needed to find a way to subdivide the buildings in order to estimate square footage.

- **Subdividing the buildings**: I'm not confident I went with the most appropriate route, but I chose to supplement building data with certificates of occupancy from DC GIS Open Data. What this represented was a set of information for registered businesses with some type of occupancy throughout DC. I created a Voronoi vector grid and then clipped that dataset by Microsoft building footprints-- thus creating a polygon dataset of units inside each building. This analysis has many limitations and assumptions: it assumes that certificates of occupancy are distributed appropriately by addresses, it assumes that the certificate dataset is mostly complete, it assumes that the X,Y location of these certificates somewhat match the midpoint of buildings, thus approximating space between units.
  
  <img width="45%" alt="Screen Shot 2022-03-20 at 5 28 24 PM" src="https://user-images.githubusercontent.com/95954591/159192571-2e8593f6-0b3d-4f41-9fc2-51861f731b85.png">   <img width="45%" alt="Screen Shot 2022-03-20 at 5 28 35 PM" src="https://user-images.githubusercontent.com/95954591/159192579-a2514dc1-858d-45ce-8e2c-e8bbbfa82383.png">

- **Estimating Square Footage**: I chose several "data points" for estimating square footage: 
  1) ST_Area spatial calculation of the unit, after subdividing the building, with some adjustments for bars showing "multiple floors" in their certificates. This number looked greatly 'off' with some extremely large spaces, and some unexpectedly small spaces.
  2) Taking occupancy numbers and creating a "reverse calculation" for square footage. This _assumes_ about 15 square feet of space for each individual (taken from DC Codes) that the building has ~50% kitchen/bar/stockroom/etc space. So a square footage reverse calculation might look like: `(Occupancy # *15)*2`
  3) Taking an average of those two numbers
  4) In the case that a building didn't have occupancy listed, or didn't intersect with any building footprints. I created a calculated square footage with the average of the nearest 5 buildings.
  5) In addition to square footage, I included occupancy wherever available.
  
  Potentially alternative methods:
  
  - There are likely better ways to subdivide buildings and allocate different unit sizes. They'd likely require additional data points: 1) collecting POIs for each building with a bar in it, perhaps 2) satellite imagery/image recognition, 3) taking an average distribution of bar sizes in the city, etc.

- Calculations for square footage were rudimentary, and didn't account well for multi-level buildings, open-air spaces (ie -- a building with a first floor and a balcony), etc. This calculation could be improved by taking a normal distribution of spaces, or additional data points. 

### 3) API Generation
I used the most rudimentary implementation of an API, connected to a single postgres table. In a future version I would include: 
  1) actually deploying the api rather than hosting locally, 
  2) including a front-end tool, something like the Mapbox search API that includes address search and returns nearest buildings
  3) boosting the postgres instance to search via index, etc

### 4) Security
In general, this project is a security catastrophe. In a future version I would include: 
  1) security credentials for the database instance
  2) security access for the API
  
