import json
import os

import psycopg2
from flask import Flask, jsonify, request
from flask_restful import Api

app = Flask(__name__)
api = Api(app)


def get_db_connection():
    conn = psycopg2.connect(host="localhost", user="postgres", database="iggy_data")
    return conn


def query_data(sql):
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute(sql)
    colnames = [desc[0] for desc in cur.description]
    results = cur.fetchall()
    cur.close()
    conn.close()
    return results, colnames


@app.route("/", methods=["GET"])
def home():
    return """<h1>Bars in DC</h1>
<p>A prototype API for DC-area Bars</p>"""


@app.route("/all")
def api_all():
    sql = "SELECT * FROM final;"
    results = query_data(sql=sql)
    return jsonify(results)


@app.route("/bars", methods=["GET"])
def api_location():
    query_parameters = request.args.get("location")
    print(query_parameters)
    location = query_parameters

    if location:
        sql = """
            select 
                name as "Name",
                avg_sq_footage as "Square Footage",
                Occupancy as "Expected Full Occupancy",
                trunc(ST_Distance(ST_Transform(ST_SetSRID(ST_POINT(%s),4326), 3857), ST_Transform(ST_SetSRID(ST_POINT(x,y),4326), 3857))::numeric,2) as "Distance From Location (Meters)",
                liquor_license as "Liquor License"
            from final
            order by "Distance From Location (Meters)"
            limit 5;
        """
        sql = sql % location
        results, colnames = query_data(sql=sql)
        json_data = []
        for result in results:
            json_data.append(dict(zip(colnames, result)))
        return jsonify(json_data)


if __name__ == "__main__":
    app.run()  # run/hosted locally for now
