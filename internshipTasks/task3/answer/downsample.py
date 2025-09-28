import os
from pathlib import Path
import pandas as pd
import warnings

warnings.filterwarnings("ignore", category=FutureWarning)
warnings.filterwarnings("ignore", message=".*infer_datetime_format.*")
warnings.filterwarnings("ignore", message=".*'T' is deprecated.*")

TS_CANDIDATES = ("timestamp", "time", "datetime", "date", "ts")

def find_ts_col(cols):
    lowered = [c.lower() for c in cols]
    for t in TS_CANDIDATES:
        if t in lowered:
            return cols[lowered.index(t)]
    return None

def aggregate_df(df, freq):
    col_map = {c.lower(): c for c in df.columns}
    agg = {}
    if "open" in col_map: agg[col_map["open"]] = "first"
    if "high" in col_map: agg[col_map["high"]] = "max"
    if "low" in col_map:  agg[col_map["low"]] = "min"
    if "close" in col_map: agg[col_map["close"]] = "last"
    if "volume" in col_map: agg[col_map["volume"]] = "sum"
    for c in df.select_dtypes(include="number").columns:
        if c not in agg: agg[c] = "mean"
    for c in df.select_dtypes(exclude="number").columns:
        if c not in agg: agg[c] = "first"
    return df.resample(freq).agg(agg).dropna(how="all")

def process_file(in_path: Path, out_dir: Path, freq: str = "1T", compress: bool = True):
    try:
        sample = pd.read_csv(in_path, nrows=50)
    except Exception as e:
        print(f"Skip {in_path.name}: read error {e}")
        return 0
    ts_col = find_ts_col(sample.columns.tolist())
    if not ts_col:
        # try parsing any column
        for c in sample.columns:
            try:
                pd.to_datetime(sample[c], errors="raise")
                ts_col = c
                break
            except Exception:
                continue
    if not ts_col:
        print(f"Skip {in_path.name}: no timestamp column")
        return 0

    df = pd.read_csv(in_path, parse_dates=[ts_col], infer_datetime_format=True)
    df = df.set_index(pd.to_datetime(df[ts_col], errors="coerce")).sort_index()
    df.index.name = "date"
    down = aggregate_df(df, freq)
    if down.empty:
        print(f"{in_path.name}: empty after resample")
        return 0

    out_path = out_dir / in_path.name
    if compress:
        out_path = out_path.with_suffix(out_path.suffix + ".gz")
        down.to_csv(out_path, index=True, compression="gzip")
    else:
        down.to_csv(out_path, index=True)
    print(f"Wrote {out_path} ({len(down)} rows)")
    return len(down)

def downsample_dir(input_dir: str, output_dir: str, freq: str = "1T", compress: bool = True):
    inp = Path(input_dir)
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)
    files = sorted([p for p in inp.glob("*.csv")])
    total = 0
    for p in files:
        total += process_file(p, out, freq, compress)
    print(f"Downsampled {len(files)} files -> {output_dir}, total rows: {total}")
    return total

if __name__ == "__main__":
    # simple CLI used by run.ps1
    import sys
    in_dir = sys.argv[1] if len(sys.argv) > 1 else "internshipTasks/task3/data_subset"
    out_dir = sys.argv[2] if len(sys.argv) > 2 else in_dir + "_downsampled"
    freq = sys.argv[3] if len(sys.argv) > 3 else "1T"
    compress = True
    downsample_dir(in_dir, out_dir, freq, compress)