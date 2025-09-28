from fastapi import FastAPI, Query
from pymongo import MongoClient
from datetime import datetime
from typing import List, Optional, Dict, Any
import logging

try:
    from influxdb_client import InfluxDBClient
except Exception:
    InfluxDBClient = None

class FASTAPI:
    def __init__(
        self,
        uri: str,
        db_name: str,
        collection_name: str,
        influx_config: Optional[Dict[str, str]] = None
    ):
        """
        influx_config example:
        {
            "url": "http://localhost:8086",
            "token": "my-token",
            "org": "my-org",
            "bucket": "intraday"
        }
        """
        self.client = MongoClient(uri)
        self.db = self.client[db_name]
        self.collection = self.db[collection_name]
        self.app = FastAPI()
        self.influx_config = influx_config
        self.influx_client = None
        if influx_config and InfluxDBClient is not None:
            try:
                self.influx_client = InfluxDBClient(
                    url=influx_config["url"],
                    token=influx_config["token"],
                    org=influx_config["org"]
                )
            except Exception as e:
                logging.warning("Failed to create InfluxDB client: %s", e)
                self.influx_client = None

        @self.app.get("/timeseries")
        def get_timeseries(
            tickers: str = Query(..., description="Comma-separated tickers"),
            start: str = Query(..., description="ISO start datetime, e.g. 2023-08-01T09:15:00"),
            end: str = Query(..., description="ISO end datetime, e.g. 2023-08-01T15:30:00"),
            fields: Optional[str] = Query("open,close,high,low,volume", description="Comma-separated fields"),
            db: Optional[str] = Query("mongo", description='Source DB: "mongo" or "influx"')
        ):
            """
            Returns timeseries across tickers and datetime range.
            Response: list of objects { "ticker": str, "date": ISO8601 str, <fields> }
            """
            # parse inputs
            ticker_list = [t.strip() for t in tickers.split(",") if t.strip()]
            # parse datetimes (accept date-only YYYY-MM-DD or full ISO)
            def _parse_dt(s: str) -> datetime:
                try:
                    return datetime.fromisoformat(s)
                except Exception:
                    return datetime.strptime(s, "%Y-%m-%d")
            start_dt = _parse_dt(start)
            end_dt = _parse_dt(end)
            fields_list = [f.strip().lower() for f in fields.split(",") if f.strip()]

            if db == "mongo":
                projection = {f: 1 for f in fields_list}
                projection["date"] = 1
                projection["ticker"] = 1
                cursor = self.collection.find(
                    {"ticker": {"$in": ticker_list}, "date": {"$gte": start_dt, "$lte": end_dt}},
                    projection
                ).sort([("ticker", 1), ("date", 1)])
                out = []
                for doc in cursor:
                    row = {"ticker": doc.get("ticker"), "date": doc.get("date").isoformat() if doc.get("date") else None}
                    for f in fields_list:
                        row[f] = doc.get(f)
                    out.append(row)
                return out

            elif db == "influx":
                if not self.influx_client:
                    return {"error": "Influx client not configured on this FASTAPI instance."}
                query_api = self.influx_client.query_api()
                # Build flux query that filters by tickers and requested fields. We'll pivot so each time contains fields as columns.
                tickers_filter = " or ".join([f'r["ticker"] == "{t}"' for t in ticker_list])
                # fields in influx are measured in _field column; we filter and then pivot to wide table
                fields_filter = " or ".join([f'r["_field"] == "{f}"' for f in fields_list])
                flux = f'''
from(bucket: "{self.influx_config["bucket"]}")
  |> range(start: {start_dt.isoformat()}, stop: {end_dt.isoformat()})
  |> filter(fn: (r) => r["_measurement"] == "quotes" and ({tickers_filter}) and ({fields_filter}))
  |> pivot(rowKey:["_time","ticker"], columnKey: ["_field"], valueColumn: "_value")
  |> keep(columns: ["_time","ticker",{",".join([f'"{f}"' for f in fields_list])}])
'''
                try:
                    tables = query_api.query(flux, org=self.influx_config["org"])
                except Exception as e:
                    logging.error("Influx query failed: %s", e)
                    return {"error": f"Influx query failed: {e}"}
                out = []
                for table in tables:
                    for record in table.records:
                        t = record.values
                        # record.values will include keys such as _time, ticker and fields
                        row = {
                            "ticker": t.get("ticker"),
                            "date": t.get("_time").isoformat() if t.get("_time") else None
                        }
                        for f in fields_list:
                            row[f] = t.get(f)
                        out.append(row)
                # sort by ticker/date
                out.sort(key=lambda r: (r.get("ticker") or "", r.get("date") or ""))
                return out

            else:
                return {"error": f"unsupported db: {db}"}

    def get_app(self):
        return self.app