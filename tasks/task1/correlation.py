import pandas as pd
from pymongo import MongoClient
from sklearn.cluster import KMeans

class StockClusterer:
    def __init__(self, mongo_uri, db_name="sse", collection_name="equities"):
        self.client = MongoClient(mongo_uri)
        self.collection = self.client[db_name][collection_name]

    def fetch_data(self, tickers, start, end, field="close"):
        data = {}
        for ticker in tickers:
            cursor = self.collection.find(
                {"ticker": ticker, "date": {"$gte": pd.to_datetime(start), "$lte": pd.to_datetime(end)}},
                {field: 1, "date": 1}
            )
            df = pd.DataFrame(list(cursor))
            df = df.sort_values("date")
            data[ticker] = df[field].values
        return pd.DataFrame(data)

    def compute_correlation(self, df):
        return df.corr()

    def cluster_stocks(self, df, n_clusters=3):
        corr_matrix = self.compute_correlation(df)
        # Use absolute correlation values for clustering
        kmeans = KMeans(n_clusters=n_clusters, random_state=42)
        labels = kmeans.fit_predict(corr_matrix.fillna(0).values)
        return dict(zip(corr_matrix.columns, labels))

# Example usage:
# mongo_uri = "mongodb+srv://dbUser:Kim06082006@cluster.9x7imc6.mongodb.net/?retryWrites=true&w=majority&appName=Cluster"
# clusterer = StockClusterer(mongo_uri)
# tickers = ["600519.SS", "000001.SS", "601398.SS"]
# df = clusterer.fetch_data(tickers, "2022-01-01", "2023-01-01")
# clusters = clusterer.cluster_stocks(df, n_clusters=2)
# print(clusters)