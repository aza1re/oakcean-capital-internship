from fastapi import FastAPI
from pymongo import MongoClient
from datetime import datetime
from typing import List, Optional

class FASTAPI:
    def __init__(self, uri: str, db_name: str, collection_name: str):
        self.client = MongoClient(uri)
        self.db = self.client[db_name]
        self.collection = self.db[collection_name]
        self.app = FastAPI()

        @self.app.get("/timeseries")
        def get_timeseries(
            ticker: str,
            start: str,
            end: str,
            fields: Optional[str] = "open,close,high,low,volume"
        ):
            start_dt = datetime.strptime(start, "%Y-%m-%d")
            end_dt = datetime.strptime(end, "%Y-%m-%d")
            projection = {f: 1 for f in fields.split(",")}
            projection["date"] = 1
            data = list(self.collection.find(
                {"ticker": ticker, "date": {"$gte": start_dt, "$lte": end_dt}},
                projection
            ))
            return data

    def get_app(self):
        return self.app