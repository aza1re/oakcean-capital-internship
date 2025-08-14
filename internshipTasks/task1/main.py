from fastapi import FastAPI
from pymongo.mongo_client import MongoClient
from pymongo.server_api import ServerApi
from datetime import datetime
import yfinance as yf
import pandas as pd
from tqdm import tqdm

from correlation import StockClusterer
from mrs import MeanReversionStrategy
from utils.FASTAPI import FASTAPI  # <-- Import the new class

# --- MongoDB and FastAPI Setup using the new class ---
uri = "mongodb+srv://dbUser:Kim06082006@cluster.9x7imc6.mongodb.net/?retryWrites=true&w=majority&appName=Cluster"
db_name = "sse"
collection_name = "equities"

mongo_api = FASTAPI(uri, db_name, collection_name)
app = mongo_api.get_app()

# --- Data Download and Storage (unchanged) ---
client = MongoClient(uri, server_api=ServerApi('1'))
try:
    client.admin.command('ping')
    print("Pinged your deployment. You successfully connected to MongoDB!")
except Exception as e:
    print(e)

db = client[db_name]
collection = db[collection_name]

tickers = ["600519.SS", "000001.SS", "601398.SS"]
for ticker in tqdm(tickers, desc="Tickers"):
    df = yf.download(ticker, start="2022-01-01", end="2023-01-01")
    df.reset_index(inplace=True)
    for idx, row in tqdm(df.iterrows(), total=len(df), desc=f"{ticker} rows", leave=False):
        date_value = row["Date"]
        if isinstance(date_value, pd.Series):
            date_value = date_value.iloc[0]
        date_value = pd.to_datetime(date_value).to_pydatetime()
        doc = {
            "ticker": ticker,
            "date": date_value,
            "open": float(row["Open"].iloc[0]) if isinstance(row["Open"], pd.Series) else float(row["Open"]),
            "high": float(row["High"].iloc[0]) if isinstance(row["High"], pd.Series) else float(row["High"]),
            "low": float(row["Low"].iloc[0]) if isinstance(row["Low"], pd.Series) else float(row["Low"]),
            "close": float(row["Close"].iloc[0]) if isinstance(row["Close"], pd.Series) else float(row["Close"]),
            "volume": int(row["Volume"].iloc[0]) if isinstance(row["Volume"], pd.Series) else int(row["Volume"])
        }
        collection.update_one(
            {"ticker": ticker, "date": doc["date"]},
            {"$set": doc},
            upsert=True
        )

# --- Clustering and Mean-Reversion Backtest Example ---
if __name__ == "__main__":
    # 1. Cluster stocks
    clusterer = StockClusterer(uri)
    df_prices = clusterer.fetch_data(tickers, "2022-01-01", "2023-01-01", field="close")
    clusters = clusterer.cluster_stocks(df_prices, n_clusters=2)
    print("Clusters:", clusters)

    # 2. Backtest mean-reversion strategy for each ticker
    strategy = MeanReversionStrategy(lookback=20, entry_threshold=1.0, exit_threshold=0.2)
    for ticker in tickers:
        price_series = pd.Series(df_prices[ticker])
        cumulative_returns, strategy_returns = strategy.backtest(price_series)
        print(f"{ticker} cumulative returns: {cumulative_returns.iloc[-1]:.2f}, last valid strategy return: {strategy_returns.dropna().iloc[-1]:.2f}")