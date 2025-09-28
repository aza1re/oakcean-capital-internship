"""
High-performance db loaders:
- Vectorized pandas conversions (timestamps, numerics)
- Chunked insert_many for MongoDB (ordered=False)
- Concurrent per-file uploads using ThreadPoolExecutor
- Line-protocol batching for Influx (faster than per-row Point objects)
- Per-file row-level tqdm progress bars
"""
import os
import time
import math
import warnings
from typing import Optional, Dict, List
from concurrent.futures import ThreadPoolExecutor, as_completed

import pandas as pd
from tqdm import tqdm
import re

# optional imports; functions will skip targets if missing
try:
    from pymongo import MongoClient
    from pymongo.errors import PyMongoError
except Exception:
    MongoClient = None
    PyMongoError = Exception

try:
    from influxdb_client import InfluxDBClient
except Exception:
    InfluxDBClient = None

warnings.filterwarnings("ignore", message="Discarding nonzero nanoseconds in conversion.")

DATA_DIR_DEFAULT = os.path.join("internshipTasks", "task3", "data")


def _infer_timestamp(df: pd.DataFrame) -> pd.Series:
    for col in ["Datetime", "datetime", "Timestamp", "timestamp", "time", "Time"]:
        if col in df.columns:
            return pd.to_datetime(df[col], errors="coerce")
    if "Date" in df.columns and "Time" in df.columns:
        return pd.to_datetime(df["Date"].astype(str) + " " + df["Time"].astype(str), errors="coerce")
    return pd.to_datetime(df.index, errors="coerce")


def _chunked(iterable: List, n: int):
    for i in range(0, len(iterable), n):
        yield iterable[i:i + n]


def load_to_mongo(mongo_uri: str,
                  db_name: str = "intraday",
                  coll_name: str = "quotes",
                  data_dir: Optional[str] = None,
                  batch_size: int = 5000,
                  show_progress: bool = True,
                  max_workers: int = 8,
                  max_retries: int = 2,
                  drop_indexes_before_load: bool = False):
    """
    Fast Mongo ingestion with per-file row tqdm bars.
    """
    if MongoClient is None:
        raise RuntimeError("pymongo not installed; cannot load to MongoDB")

    data_dir = data_dir or DATA_DIR_DEFAULT
    files = sorted([f for f in os.listdir(data_dir)
                    if f.lower().endswith(".csv") or f.lower().endswith(".csv.gz")])
    if not files:
        return 0

    client = MongoClient(mongo_uri, serverSelectionTimeoutMS=5000, socketTimeoutMS=20000)
    coll = client[db_name][coll_name]

    if drop_indexes_before_load:
        try:
            coll.drop_indexes()
            if show_progress:
                tqdm.write("Dropped indexes on target collection to speed ingestion.")
        except Exception as e:
            if show_progress:
                tqdm.write(f"Warning: failed to drop indexes: {e}")

    def process_file(fn: str):
        path = os.path.join(data_dir, fn)
        ticker = os.path.splitext(fn)[0]
        try:
            df = pd.read_csv(path)
            if df.empty:
                return 0
        except Exception as e:
            if show_progress:
                tqdm.write(f"Skip {fn}: {e}")
            return 0

        # prepare per-file row progress
        row_total = len(df)
        row_bar = tqdm(total=row_total, desc=f"rows:{ticker}", unit="row", leave=False) if show_progress else None

        # vectorized transforms
        ts = _infer_timestamp(df)
        df = df.copy()
        df["date"] = pd.to_datetime(ts, errors="coerce")
        # normalize expected numeric columns
        col_map = {}
        for c in df.columns:
            lc = c.strip().lower()
            if lc in ["open", "high", "low", "close", "volume"]:
                col_map[c] = lc
        df = df.rename(columns=col_map)
        for col in ["open", "high", "low", "close"]:
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors="coerce")
        if "volume" in df.columns:
            df["volume"] = pd.to_numeric(df["volume"], errors="coerce")

        # keep only the fields we want
        fields = ["date", "open", "high", "low", "close", "volume"]
        present = [f for f in fields if f in df.columns]
        df_sub = df[present].where(pd.notnull(df[present]), None)
        # add ticker column
        df_sub["ticker"] = ticker

        records = df_sub.to_dict(orient="records")
        inserted = 0
        processed_rows = 0
        for chunk in _chunked(records, batch_size):
            attempt = 0
            chunk_len = len(chunk)
            while attempt <= max_retries:
                try:
                    coll.insert_many(chunk, ordered=False)
                    inserted += chunk_len
                    processed_rows += chunk_len
                    if row_bar is not None:
                        row_bar.update(chunk_len)
                    break
                except PyMongoError as e:
                    attempt += 1
                    if attempt > max_retries:
                        if show_progress:
                            tqdm.write(f"Dropping chunk for {fn} after {max_retries} retries: {e}")
                        # consider the rows as processed for progress purposes
                        processed_rows += chunk_len
                        if row_bar is not None:
                            row_bar.update(chunk_len)
                        break
                    wait = 2 ** attempt
                    time.sleep(wait)
        # close row bar
        if row_bar is not None:
            remaining = row_total - row_bar.n
            if remaining > 0:
                row_bar.update(remaining)
            row_bar.close()
        return inserted

    total_inserted = 0
    max_workers = max(1, min(max_workers, len(files)))
    with ThreadPoolExecutor(max_workers=max_workers) as ex:
        futures = {ex.submit(process_file, f): f for f in files}
        if show_progress:
            pbar = tqdm(total=len(files), desc="Mongo files", unit="file")
            for fut in as_completed(futures):
                f = futures[fut]
                try:
                    ins = fut.result()
                    total_inserted += ins
                except Exception as e:
                    tqdm.write(f"Error processing {f}: {e}")
                pbar.update(1)
                pbar.set_postfix({"inserted": total_inserted})
            pbar.close()
        else:
            for fut in as_completed(futures):
                total_inserted += fut.result()

    client.close()
    return total_inserted


def _df_to_line_protocol(df: pd.DataFrame, ticker: str, measurement: str = "quotes"):
    """
    Convert dataframe to Influx line protocol strings for a single ticker.
    """
    if "timestamp" in df.columns:
        ts = pd.to_datetime(df["timestamp"], errors="coerce")
    elif "date" in df.columns:
        ts = pd.to_datetime(df["date"], errors="coerce")
    else:
        ts = pd.to_datetime(df.index, errors="coerce")
    dfc = df.copy()
    # use view if available, otherwise compute ns
    try:
        dfc["ts_ns"] = (ts.view("int64"))
    except Exception:
        dfc["ts_ns"] = (ts.astype("int64"))
    # build field pairs
    field_cols = []
    if "open" in dfc.columns:
        dfc["open_f"] = dfc["open"].apply(lambda v: f"open={float(v)}" if pd.notna(v) else "")
        field_cols.append("open_f")
    if "high" in dfc.columns:
        dfc["high_f"] = dfc["high"].apply(lambda v: f"high={float(v)}" if pd.notna(v) else "")
        field_cols.append("high_f")
    if "low" in dfc.columns:
        dfc["low_f"] = dfc["low"].apply(lambda v: f"low={float(v)}" if pd.notna(v) else "")
        field_cols.append("low_f")
    if "close" in dfc.columns:
        dfc["close_f"] = dfc["close"].apply(lambda v: f"close={float(v)}" if pd.notna(v) else "")
        field_cols.append("close_f")
    if "volume" in dfc.columns:
        dfc["vol_f"] = dfc["volume"].apply(lambda v: f"volume={int(v)}i" if pd.notna(v) else "")
        field_cols.append("vol_f")

    lines = []
    for _, row in dfc.iterrows():
        parts = [row[c] for c in field_cols if row[c]]
        if not parts:
            continue
        fields_str = ",".join(parts)
        ttag = str(ticker).replace(" ", "\\ ")
        line = f"{measurement},ticker={ttag} {fields_str} {int(row['ts_ns'])}"
        lines.append(line)
    return lines


def load_to_influx(influx_cfg: Dict[str, str],
                   data_dir: Optional[str] = None,
                   batch_size: int = 5000,
                   show_progress: bool = True,
                   max_workers: int = 4):
    """
    Fast Influx ingestion with per-file line/row tqdm bars.
    """
    if InfluxDBClient is None:
        raise RuntimeError("influxdb_client not installed; cannot load to InfluxDB")

    data_dir = data_dir or DATA_DIR_DEFAULT
    files = sorted([f for f in os.listdir(data_dir)
                    if f.lower().endswith(".csv") or f.lower().endswith(".csv.gz")])
    if not files:
        return 0

    def process_file(fn: str):
        path = os.path.join(data_dir, fn)
        ticker = re.sub(r'(?i)\.csv(?:\.gz)?$', '', fn)
        try:
            df = pd.read_csv(path)
            if df.empty:
                return 0
        except Exception as e:
            if show_progress:
                tqdm.write(f"Skip {fn}: {e}")
            return 0

        ts = _infer_timestamp(df)
        df = df.copy()
        df["timestamp"] = ts
        col_map = {}
        for c in df.columns:
            lc = c.strip().lower()
            if lc in ["open", "high", "low", "close", "volume"]:
                col_map[c] = lc
        df = df.rename(columns=col_map)
        for col in ["open", "high", "low", "close"]:
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors="coerce")
        if "volume" in df.columns:
            df["volume"] = pd.to_numeric(df["volume"], errors="coerce")

        lines = _df_to_line_protocol(df, ticker)
        if not lines:
            return 0

        line_total = len(lines)
        line_bar = tqdm(total=line_total, desc=f"lines:{ticker}", unit="line", leave=False) if show_progress else None

        inserted = 0
        client = InfluxDBClient(url=influx_cfg["url"], token=influx_cfg["token"], org=influx_cfg["org"])
        write_api = client.write_api()
        for chunk in _chunked(lines, batch_size):
            lp = "\n".join(chunk)
            try:
                write_api.write(bucket=influx_cfg["bucket"], org=influx_cfg["org"], record=lp)
                inserted += len(chunk)
                if line_bar is not None:
                    line_bar.update(len(chunk))
            except Exception as e:
                if show_progress:
                    tqdm.write(f"Influx write error for {fn}: {e}")
                if line_bar is not None:
                    line_bar.update(len(chunk))  # Update progress even if the chunk fails
        if line_bar is not None:
            remaining = line_total - line_bar.n
            if remaining > 0:
                line_bar.update(remaining)
            line_bar.close()

        write_api.__del__()
        client.close()
        return inserted

    total_written = 0
    max_workers = max(1, min(max_workers, len(files)))
    with ThreadPoolExecutor(max_workers=max_workers) as ex:
        futures = {ex.submit(process_file, f): f for f in files}
        if show_progress:
            pbar = tqdm(total=len(files), desc="Influx files", unit="file")
            for fut in as_completed(futures):
                f = futures[fut]
                try:
                    cnt = fut.result()
                    total_written += cnt
                except Exception as e:
                    tqdm.write(f"Error processing {f}: {e}")
                pbar.update(1)
                pbar.set_postfix({"written": total_written})
            pbar.close()
        else:
            for fut in as_completed(futures):
                total_written += fut.result()

    return total_written