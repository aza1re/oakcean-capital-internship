# Complete run.ps1 — starts local InfluxDB and MongoDB (Docker), downsamples/samples data,
# ingests to DBs, starts FastAPI (uvicorn) via a temporary script so the app imports from utils.FASTAPI,
# ensures unbuffered Python IO so tqdm progress bars render, runs benchmark, then cleans up.

param(
    [string]$CondaEnv = "oakceancapital"
)

# Hardcoded configuration (edit if needed)
$MONGO_URI = "mongodb+srv://dbUser:Kim06082006@cluster.9x7imc6.mongodb.net/?retryWrites=true&w=majority&appName=Cluster"
$START_LOCAL_INFLUX = $true
$LOCAL_INFLUX_NAME = "influxdb"
$LOCAL_INFLUX_URL = "http://localhost:8086"
$LOCAL_INFLUX_TOKEN = "supersecrettoken"
$LOCAL_INFLUX_ORG = "oakcean-org"
$LOCAL_INFLUX_BUCKET = "intraday"

# Local Mongo config (dev)
$START_LOCAL_MONGO = $true
$LOCAL_MONGO_NAME = "mongodb"
$LOCAL_MONGO_PORT = 27017
$LOCAL_MONGO_IMAGE = "mongo:6.0"
$LOCAL_MONGO_VOLUME = "mongo-data"
$MaxBytes = 512 * 1024 * 1024

function Ensure-Conda {
    if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
        $possible = "$env:USERPROFILE\miniconda3\Scripts\conda.exe"
        if (Test-Path $possible) {
            $hook = & $possible "shell.powershell" "hook" 2>$null
            if ($LASTEXITCODE -eq 0 -and $hook) { Invoke-Expression $hook }
        }
    }
    if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
        Write-Error "conda not found. Open a PowerShell where conda is available or install Miniconda."
        exit 1
    }
}
Ensure-Conda
conda activate $CondaEnv

# Save previous env and configure Python env so tqdm and other realtime output work
$__prev_PYTHONWARNINGS = $env:PYTHONWARNINGS
$__prev_PYTHONUNBUFFERED = $env:PYTHONUNBUFFERED
$__prev_PYTHONIOENCODING = $env:PYTHONIOENCODING

$env:PYTHONWARNINGS = "ignore::FutureWarning"
$env:PYTHONUNBUFFERED = "1"
$env:PYTHONIOENCODING = "utf-8"

# helper to always add -u and -W ignore::FutureWarning to python subprocesses
function Invoke-Python {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $Args
    )
    $pa = @("-u","-W","ignore::FutureWarning") + $Args
    & python.exe @pa
    return $LASTEXITCODE
}

# Repo root (assume running from repo root)
$RepoRoot = (Get-Location).Path
$DataDirRelOrig = "internshipTasks/task3/data_subset"

# downsample script path
$dsScript = Join-Path $RepoRoot "internshipTasks/task3/answer/downsample.py"
if (-not (Test-Path $dsScript)) {
    Write-Error "Downsample script not found: $dsScript"
    # restore env before exit
    if ($null -ne $__prev_PYTHONWARNINGS) { $env:PYTHONWARNINGS = $__prev_PYTHONWARNINGS } else { Remove-Item env:PYTHONWARNINGS -ErrorAction SilentlyContinue }
    if ($null -ne $__prev_PYTHONUNBUFFERED) { $env:PYTHONUNBUFFERED = $__prev_PYTHONUNBUFFERED } else { Remove-Item env:PYTHONUNBUFFERED -ErrorAction SilentlyContinue }
    if ($null -ne $__prev_PYTHONIOENCODING) { $env:PYTHONIOENCODING = $__prev_PYTHONIOENCODING } else { Remove-Item env:PYTHONIOENCODING -ErrorAction SilentlyContinue }
    exit 1
}

# Candidate aggregation resolutions (coarser -> smaller output)
$freqCandidates = @("1min","5min","15min","30min","60min","360min","1D")

# try downsampling iteratively until total size <= $MaxBytes
$selectedOut = $null
foreach ($freq in $freqCandidates) {
    $outDir = "${DataDirRelOrig}_down_${freq}"

    if (Test-Path $outDir) {
        $existingSize = (Get-ChildItem -Path $outDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $existingSize = $existingSize -as [uint64]
        if (-not $existingSize) { $existingSize = 0 }
        Write-Output "Found existing downsample directory $outDir (size: $([math]::Round($existingSize/1MB,2)) MB)"
        if ($existingSize -le $MaxBytes) {
            Write-Output "Existing downsample fits size limit; selecting $outDir"
            $selectedOut = $outDir
            break
        } else {
            Write-Output "Existing downsample too large; removing and re-creating $outDir"
            Remove-Item -Recurse -Force $outDir
        }
    }

    Write-Output "Trying downsample freq=$freq -> $outDir ..."
    Invoke-Python $dsScript $DataDirRelOrig $outDir $freq
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Downsample script exited non-zero (code $LASTEXITCODE) for freq=$freq. Trying next."
        if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
        continue
    }
    $size = (Get-ChildItem -Path $outDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    $size = $size -as [uint64]
    if (-not $size) { $size = 0 }
    Write-Output "Result size: $([math]::Round($size/1MB,2)) MB"
    if ($size -le $MaxBytes) {
        $selectedOut = $outDir
        break
    } else {
        Write-Output "Size > limit ($([math]::Round($MaxBytes/1MB,2)) MB). Removing $outDir and trying coarser freq."
        Remove-Item -Recurse -Force $outDir
    }
}

if (-not $selectedOut) {
    $sampleFractions = @(0.1,0.05,0.02,0.01)
    foreach ($frac in $sampleFractions) {
        $outDir = "${DataDirRelOrig}_sample_${(100*$frac)%100}pct"
        if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
        Write-Output "Trying random sampling frac=$frac -> $outDir ..."
        $py = @"
import os, sys
import pandas as pd
inp = sys.argv[1]; out = sys.argv[2]; frac = float(sys.argv[3])
os.makedirs(out, exist_ok=True)
for fn in sorted([f for f in os.listdir(inp) if f.lower().endswith('.csv')]):
    p = os.path.join(inp, fn)
    try:
        df = pd.read_csv(p)
        if df.shape[0]==0: continue
        sdf = df.sample(frac=frac, random_state=1)
        outp = os.path.join(out, fn + '.gz')
        sdf.to_csv(outp, index=False, compression='gzip')
    except Exception as e:
        print('skip', fn, e)
"@
        $tmpPy = [IO.Path]::GetTempFileName() + ".py"
        Set-Content -Path $tmpPy -Value $py -Encoding UTF8
        Invoke-Python $tmpPy $DataDirRelOrig $outDir $frac
        Remove-Item $tmpPy -Force
        $size = (Get-ChildItem -Path $outDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if (-not $size) { $size = 0 }
        Write-Output "Sampled output size: $([math]::Round($size/1MB,2)) MB"
        if ($size -le $MaxBytes) { $selectedOut = $outDir; break }
        else { Remove-Item -Recurse -Force $outDir }
    }
}

if (-not $selectedOut) {
    Write-Error "Unable to produce downsampled data under the $([math]::Round($MaxBytes/1MB,2)) MB limit automatically. Consider using a coarser aggregation or manual sampling."
    # restore env before exit
    if ($null -ne $__prev_PYTHONWARNINGS) { $env:PYTHONWARNINGS = $__prev_PYTHONWARNINGS } else { Remove-Item env:PYTHONWARNINGS -ErrorAction SilentlyContinue }
    if ($null -ne $__prev_PYTHONUNBUFFERED) { $env:PYTHONUNBUFFERED = $__prev_PYTHONUNBUFFERED } else { Remove-Item env:PYTHONUNBUFFERED -ErrorAction SilentlyContinue }
    if ($null -ne $__prev_PYTHONIOENCODING) { $env:PYTHONIOENCODING = $__prev_PYTHONIOENCODING } else { Remove-Item env:PYTHONIOENCODING -ErrorAction SilentlyContinue }
    exit 1
}

$DataDirRel = $selectedOut
Write-Output "Using data dir for ingestion: $DataDirRel"

$MarkerDir = Join-Path $RepoRoot $DataDirRel
$MongoMarker = Join-Path $MarkerDir ".mongo_ingested"
$InfluxMarker = Join-Path $MarkerDir ".influx_ingested"

$startedLocalInflux = $false
$startedLocalMongo = $false

# Start local InfluxDB container if requested
if ($START_LOCAL_INFLUX) {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Error "Docker not found in PATH; cannot start local Influx."
        # restore env before exit
        if ($null -ne $__prev_PYTHONWARNINGS) { $env:PYTHONWARNINGS = $__prev_PYTHONWARNINGS } else { Remove-Item env:PYTHONWARNINGS -ErrorAction SilentlyContinue }
        if ($null -ne $__prev_PYTHONUNBUFFERED) { $env:PYTHONUNBUFFERED = $__prev_PYTHONUNBUFFERED } else { Remove-Item env:PYTHONUNBUFFERED -ErrorAction SilentlyContinue }
        if ($null -ne $__prev_PYTHONIOENCODING) { $env:PYTHONIOENCODING = $__prev_PYTHONIOENCODING } else { Remove-Item env:PYTHONIOENCODING -ErrorAction SilentlyContinue }
        exit 1
    }

    Write-Output "Starting local InfluxDB container '$LOCAL_INFLUX_NAME'..."
    & docker rm -f $LOCAL_INFLUX_NAME 2>$null | Out-Null

    $image = $null
    try {
        $localImgs = (& docker images --format "{{.Repository}}:{{.Tag}}" 2>$null) -split "`n"
        foreach ($li in $localImgs) {
            if ($li -and ($li -match "^influxdb(:|/)" -or $li -match "^influxdb:")) { $image = $li.Trim(); break }
        }
    } catch {}

    if (-not $image) {
        Write-Output "No local Influx image found — pulling influxdb:latest ..."
        try {
            & docker pull influxdb:latest | Out-Null
            $image = "influxdb:latest"
        } catch {
            Write-Error "Failed to pull influxdb:latest. Pull manually or set START_LOCAL_INFLUX = $false."
            # restore env before exit
            if ($null -ne $__prev_PYTHONWARNINGS) { $env:PYTHONWARNINGS = $__prev_PYTHONWARNINGS } else { Remove-Item env:PYTHONWARNINGS -ErrorAction SilentlyContinue }
            if ($null -ne $__prev_PYTHONUNBUFFERED) { $env:PYTHONUNBUFFERED = $__prev_PYTHONUNBUFFERED } else { Remove-Item env:PYTHONUNBUFFERED -ErrorAction SilentlyContinue }
            if ($null -ne $__prev_PYTHONIOENCODING) { $env:PYTHONIOENCODING = $__prev_PYTHONIOENCODING } else { Remove-Item env:PYTHONIOENCODING -ErrorAction SilentlyContinue }
            exit 1
        }
    }
    Write-Output "Using Docker image: $image"

    $influxArgs = @(
        'run','-d','--name',$LOCAL_INFLUX_NAME,
        '-p','8086:8086',
        '-v','influx2-data:/var/lib/influxdb2',
        '-e',"INFLUXDB_INIT_MODE=setup",
        '-e',"INFLUXDB_INIT_USERNAME=admin",
        '-e',"INFLUXDB_INIT_PASSWORD=adminpass",
        '-e',"INFLUXDB_INIT_ORG=$LOCAL_INFLUX_ORG",
        '-e',"INFLUXDB_INIT_BUCKET=$LOCAL_INFLUX_BUCKET",
        '-e',"INFLUXDB_INIT_ADMIN_TOKEN=$LOCAL_INFLUX_TOKEN",
        $image
    )
    $cid = & docker @influxArgs
    if (-not $cid) { Write-Error "Failed to start Influx container"; # restore env before exit
        if ($null -ne $__prev_PYTHONWARNINGS) { $env:PYTHONWARNINGS = $__prev_PYTHONWARNINGS } else { Remove-Item env:PYTHONWARNINGS -ErrorAction SilentlyContinue }
        if ($null -ne $__prev_PYTHONUNBUFFERED) { $env:PYTHONUNBUFFERED = $__prev_PYTHONUNBUFFERED } else { Remove-Item env:PYTHONUNBUFFERED -ErrorAction SilentlyContinue }
        if ($null -ne $__prev_PYTHONIOENCODING) { $env:PYTHONIOENCODING = $__prev_PYTHONIOENCODING } else { Remove-Item env:PYTHONIOENCODING -ErrorAction SilentlyContinue }
        exit 1 }

    Write-Output "Waiting for InfluxDB health..."
    $max = 60; $i = 0
    while ($i -lt $max) {
        try {
            $r = Invoke-RestMethod -Uri "$LOCAL_INFLUX_URL/health" -UseBasicParsing -ErrorAction Stop
            if ($r.status -eq "pass") { break }
        } catch {}
        Start-Sleep -Seconds 1
        $i++
    }
    if ($i -ge $max) {
        Write-Error "Influx did not become ready in time; see docker logs."
        & docker logs $LOCAL_INFLUX_NAME --tail 100
        # restore env before exit
        if ($null -ne $__prev_PYTHONWARNINGS) { $env:PYTHONWARNINGS = $__prev_PYTHONWARNINGS } else { Remove-Item env:PYTHONWARNINGS -ErrorAction SilentlyContinue }
        if ($null -ne $__prev_PYTHONUNBUFFERED) { $env:PYTHONUNBUFFERED = $__prev_PYTHONUNBUFFERED } else { Remove-Item env:PYTHONUNBUFFERED -ErrorAction SilentlyContinue }
        if ($null -ne $__prev_PYTHONIOENCODING) { $env:PYTHONIOENCODING = $__prev_PYTHONIOENCODING } else { Remove-Item env:PYTHONIOENCODING -ErrorAction SilentlyContinue }
        exit 1
    }

    Write-Output "Local Influx ready."
    $startedLocalInflux = $true
}

# Start local MongoDB container if requested
if ($START_LOCAL_MONGO) {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Error "Docker not found in PATH; cannot start local MongoDB."
        # restore env before exit
        if ($null -ne $__prev_PYTHONWARNINGS) { $env:PYTHONWARNINGS = $__prev_PYTHONWARNINGS } else { Remove-Item env:PYTHONWARNINGS -ErrorAction SilentlyContinue }
        if ($null -ne $__prev_PYTHONUNBUFFERED) { $env:PYTHONUNBUFFERED = $__prev_PYTHONUNBUFFERED } else { Remove-Item env:PYTHONUNBUFFERED -ErrorAction SilentlyContinue }
        if ($null -ne $__prev_PYTHONIOENCODING) { $env:PYTHONIOENCODING = $__prev_PYTHONIOENCODING } else { Remove-Item env:PYTHONIOENCODING -ErrorAction SilentlyContinue }
        exit 1
    }

    Write-Output "Starting local MongoDB container '$LOCAL_MONGO_NAME'..."
    & docker rm -f $LOCAL_MONGO_NAME 2>$null | Out-Null

    $mImg = $null
    try {
        $localImgs = (& docker images --format "{{.Repository}}:{{.Tag}}" 2>$null) -split "`n"
        foreach ($li in $localImgs) {
            if ($li -and ($li -match "^mongo(:|/)" -or $li -match "^mongo:")) { $mImg = $li.Trim(); break }
        }
    } catch {}

    if (-not $mImg) {
        Write-Output "No local Mongo image found — pulling $LOCAL_MONGO_IMAGE ..."
        try {
            & docker pull $LOCAL_MONGO_IMAGE | Out-Null
            $mImg = $LOCAL_MONGO_IMAGE
        } catch {
            Write-Error "Failed to pull $LOCAL_MONGO_IMAGE. Pull manually or set START_LOCAL_MONGO = $false."
            # restore env before exit
            if ($null -ne $__prev_PYTHONWARNINGS) { $env:PYTHONWARNINGS = $__prev_PYTHONWARNINGS } else { Remove-Item env:PYTHONWARNINGS -ErrorAction SilentlyContinue }
            if ($null -ne $__prev_PYTHONUNBUFFERED) { $env:PYTHONUNBUFFERED = $__prev_PYTHONUNBUFFERED } else { Remove-Item env:PYTHONUNBUFFERED -ErrorAction SilentlyContinue }
            if ($null -ne $__prev_PYTHONIOENCODING) { $env:PYTHONIOENCODING = $__prev_PYTHONIOENCODING } else { Remove-Item env:PYTHONIOENCODING -ErrorAction SilentlyContinue }
            exit 1
        }
    }

    $mongoArgs = @(
        'run','-d','--name',$LOCAL_MONGO_NAME,
        '-p',"${LOCAL_MONGO_PORT}:27017",
        '-v',"${LOCAL_MONGO_VOLUME}:/data/db",
        $mImg
    )
    $cid = & docker @mongoArgs
    if (-not $cid) { Write-Error "Failed to start Mongo container"; # restore env before exit
        if ($null -ne $__prev_PYTHONWARNINGS) { $env:PYTHONWARNINGS = $__prev_PYTHONWARNINGS } else { Remove-Item env:PYTHONWARNINGS -ErrorAction SilentlyContinue }
        if ($null -ne $__prev_PYTHONUNBUFFERED) { $env:PYTHONUNBUFFERED = $__prev_PYTHONUNBUFFERED } else { Remove-Item env:PYTHONUNBUFFERED -ErrorAction SilentlyContinue }
        if ($null -ne $__prev_PYTHONIOENCODING) { $env:PYTHONIOENCODING = $__prev_PYTHONIOENCODING } else { Remove-Item env:PYTHONIOENCODING -ErrorAction SilentlyContinue }
        exit 1 }

    Write-Output "Waiting for MongoDB port $LOCAL_MONGO_PORT to be open..."
    $max = 60; $i = 0
    while ($i -lt $max) {
        try {
            $res = Test-NetConnection -ComputerName "127.0.0.1" -Port $LOCAL_MONGO_PORT -WarningAction SilentlyContinue
            if ($res.TcpTestSucceeded) { break }
        } catch {}
        Start-Sleep -Seconds 1
        $i++
    }
    if ($i -ge $max) {
        Write-Error "Mongo did not become ready in time; see docker logs."
        & docker logs $LOCAL_MONGO_NAME --tail 100
        # restore env before exit
        if ($null -ne $__prev_PYTHONWARNINGS) { $env:PYTHONWARNINGS = $__prev_PYTHONWARNINGS } else { Remove-Item env:PYTHONWARNINGS -ErrorAction SilentlyContinue }
        if ($null -ne $__prev_PYTHONUNBUFFERED) { $env:PYTHONUNBUFFERED = $__prev_PYTHONUNBUFFERED } else { Remove-Item env:PYTHONUNBUFFERED -ErrorAction SilentlyContinue }
        if ($null -ne $__prev_PYTHONIOENCODING) { $env:PYTHONIOENCODING = $__prev_PYTHONIOENCODING } else { Remove-Item env:PYTHONIOENCODING -ErrorAction SilentlyContinue }
        exit 1
    }

    Write-Output "Local Mongo ready."
    $MONGO_URI = "mongodb://127.0.0.1:${LOCAL_MONGO_PORT}"
    $startedLocalMongo = $true
    Write-Output "Overriding MONGO_URI -> $MONGO_URI"
}

# Ingest to MongoDB
if ($MONGO_URI) {
    if (Test-Path $MongoMarker) {
        Write-Output "Skipping Mongo ingestion — marker found: $MongoMarker"
    } else {
        Write-Output "Ingesting CSVs to MongoDB..."
        $py = @"
import sys
sys.path.insert(0, r'$RepoRoot')
from internshipTasks.task3.answer import db_loaders
db_loaders.load_to_mongo(r'$MONGO_URI', data_dir=r'$DataDirRel')
"@
        $tmp = [IO.Path]::GetTempFileName() + ".py"
        Set-Content -Path $tmp -Value $py -Encoding UTF8
        Invoke-Python $tmp
        $exit = $LASTEXITCODE
        Remove-Item $tmp -Force
        if ($exit -ne 0) {
            Write-Error "Mongo ingestion script failed (exit $exit)."
            if ($startedLocalInflux) { & docker stop $LOCAL_INFLUX_NAME | Out-Null; & docker rm $LOCAL_INFLUX_NAME | Out-Null }
            if ($startedLocalMongo) { & docker stop $LOCAL_MONGO_NAME | Out-Null; & docker rm $LOCAL_MONGO_NAME | Out-Null }
            # restore env before exit
            if ($null -ne $__prev_PYTHONWARNINGS) { $env:PYTHONWARNINGS = $__prev_PYTHONWARNINGS } else { Remove-Item env:PYTHONWARNINGS -ErrorAction SilentlyContinue }
            if ($null -ne $__prev_PYTHONUNBUFFERED) { $env:PYTHONUNBUFFERED = $__prev_PYTHONUNBUFFERED } else { Remove-Item env:PYTHONUNBUFFERED -ErrorAction SilentlyContinue }
            if ($null -ne $__prev_PYTHONIOENCODING) { $env:PYTHONIOENCODING = $__prev_PYTHONIOENCODING } else { Remove-Item env:PYTHONIOENCODING -ErrorAction SilentlyContinue }
            exit 1
        }
        Set-Content -Path $MongoMarker -Value ("Ingested to Mongo on " + (Get-Date).ToString("s")) -Force
        Write-Output "Mongo ingestion complete, marker created: $MongoMarker"
    }
} else {
    Write-Output "MONGO_URI empty -> skipping Mongo ingestion"
}

# Ingest to InfluxDB
if ($startedLocalInflux -or ($LOCAL_INFLUX_URL -and $LOCAL_INFLUX_TOKEN -and $LOCAL_INFLUX_ORG -and $LOCAL_INFLUX_BUCKET)) {
    if (Test-Path $InfluxMarker) {
        Write-Output "Skipping Influx ingestion — marker found: $InfluxMarker"
    } else {
        Write-Output "Ingesting CSVs to InfluxDB..."
        $py = @"
import sys
sys.path.insert(0, r'$RepoRoot')
from internshipTasks.task3.answer import db_loaders
cfg = {'url': r'$LOCAL_INFLUX_URL', 'token': r'$LOCAL_INFLUX_TOKEN', 'org': r'$LOCAL_INFLUX_ORG', 'bucket': r'$LOCAL_INFLUX_BUCKET'}
db_loaders.load_to_influx(cfg, data_dir=r'$DataDirRel')
"@
        $tmp = [IO.Path]::GetTempFileName() + ".py"
        Set-Content -Path $tmp -Value $py -Encoding UTF8
        Invoke-Python $tmp
        $exit = $LASTEXITCODE
        Remove-Item $tmp -Force
        if ($exit -ne 0) {
            Write-Error "Influx ingestion script failed (exit $exit)."
            if ($startedLocalInflux) { & docker stop $LOCAL_INFLUX_NAME | Out-Null; & docker rm $LOCAL_INFLUX_NAME | Out-Null }
            if ($startedLocalMongo) { & docker stop $LOCAL_MONGO_NAME | Out-Null; & docker rm $LOCAL_MONGO_NAME | Out-Null }
            # restore env before exit
            if ($null -ne $__prev_PYTHONWARNINGS) { $env:PYTHONWARNINGS = $__prev_PYTHONWARNINGS } else { Remove-Item env:PYTHONWARNINGS -ErrorAction SilentlyContinue }
            if ($null -ne $__prev_PYTHONUNBUFFERED) { $env:PYTHONUNBUFFERED = $__prev_PYTHONUNBUFFERED } else { Remove-Item env:PYTHONUNBUFFERED -ErrorAction SilentlyContinue }
            if ($null -ne $__prev_PYTHONIOENCODING) { $env:PYTHONIOENCODING = $__prev_PYTHONIOENCODING } else { Remove-Item env:PYTHONIOENCODING -ErrorAction SilentlyContinue }
            exit 1
        }
        Set-Content -Path $InfluxMarker -Value ("Ingested to Influx on " + (Get-Date).ToString("s")) -Force
        Write-Output "Influx ingestion complete, marker created: $InfluxMarker"
    }
} else {
    Write-Output "Skipping Influx ingestion."
}

# Start FastAPI (uvicorn) using a temporary server script that imports utils.FASTAPI
Write-Output "Starting FastAPI (uvicorn)..."
$tmpServer = [IO.Path]::GetTempFileName() + ".py"
$server_py = @"
import sys, os
# ensure repo root is on path so utils can be imported
sys.path.insert(0, r'$RepoRoot')
from utils.FASTAPI import FASTAPI
import uvicorn

MONGO_URI = r'$MONGO_URI'
influx_cfg = {
    'url': r'$LOCAL_INFLUX_URL',
    'token': r'$LOCAL_INFLUX_TOKEN',
    'org': r'$LOCAL_INFLUX_ORG',
    'bucket': r'$LOCAL_INFLUX_BUCKET'
}

# build FastAPI app
app = FASTAPI(MONGO_URI, db_name='intraday', collection_name='quotes', influx_config=influx_cfg).get_app()

if __name__ == '__main__':
    # run uvicorn in-process; stdout/stderr will be the same as the launched python process
    uvicorn.run(app, host='127.0.0.1', port=8000)
"@
Set-Content -Path $tmpServer -Value $server_py -Encoding UTF8

# start the server with unbuffered python so stdout/stderr and tqdm flush to this console
$uv = Start-Process -FilePath python -ArgumentList @("-u", $tmpServer) -NoNewWindow -PassThru
Start-Sleep -Seconds 2

# Probe the timeseries endpoint for readiness
$readyUrl = "http://127.0.0.1:8000/timeseries?tickers=TCS&start=2023-01-02T09:15:00&end=2023-01-02T09:16:00&fields=open&db=mongo"
$max = 60; $i = 0
while ($i -lt $max) {
    try {
        Invoke-RestMethod -Uri $readyUrl -UseBasicParsing -TimeoutSec 2 | Out-Null
        break
    } catch {}
    Start-Sleep -Seconds 1
    $i++
}
if ($i -ge $max) {
    Write-Error "Server not ready within timeout. Check server output."
    if ($uv -and -not $uv.HasExited) { Stop-Process -Id $uv.Id -Force }
    if ($startedLocalInflux) { & docker stop $LOCAL_INFLUX_NAME | Out-Null; & docker rm $LOCAL_INFLUX_NAME | Out-Null }
    if ($startedLocalMongo) { & docker stop $LOCAL_MONGO_NAME | Out-Null; & docker rm $LOCAL_MONGO_NAME | Out-Null }
    # restore env before exit
    if ($null -ne $__prev_PYTHONWARNINGS) { $env:PYTHONWARNINGS = $__prev_PYTHONWARNINGS } else { Remove-Item env:PYTHONWARNINGS -ErrorAction SilentlyContinue }
    if ($null -ne $__prev_PYTHONUNBUFFERED) { $env:PYTHONUNBUFFERED = $__prev_PYTHONUNBUFFERED } else { Remove-Item env:PYTHONUNBUFFERED -ErrorAction SilentlyContinue }
    if ($null -ne $__prev_PYTHONIOENCODING) { $env:PYTHONIOENCODING = $__prev_PYTHONIOENCODING } else { Remove-Item env:PYTHONIOENCODING -ErrorAction SilentlyContinue }
    if (Test-Path $tmpServer) { Remove-Item $tmpServer -Force -ErrorAction SilentlyContinue }
    exit 1
}
Write-Output "Server is up."

# Run benchmark
Write-Output "Running benchmark..."
Invoke-Python "internshipTasks/task3/answer/main.py"

# Stop uvicorn
if ($uv -and -not $uv.HasExited) {
    Write-Output "Stopping uvicorn (PID $($uv.Id))..."
    Stop-Process -Id $uv.Id -Force
}

# cleanup temporary server file
if (Test-Path $tmpServer) { Remove-Item $tmpServer -Force -ErrorAction SilentlyContinue }

# Stop local containers if started by this script
if ($startedLocalInflux) {
    Write-Output "Stopping local Influx container '$LOCAL_INFLUX_NAME'..."
    & docker stop $LOCAL_INFLUX_NAME | Out-Null
    & docker rm $LOCAL_INFLUX_NAME | Out-Null
}
if ($startedLocalMongo) {
    Write-Output "Stopping local Mongo container '$LOCAL_MONGO_NAME'..."
    & docker stop $LOCAL_MONGO_NAME | Out-Null
    & docker rm $LOCAL_MONGO_NAME | Out-Null
}

# restore PYTHON environment variables
if ($null -ne $__prev_PYTHONWARNINGS) {
    $env:PYTHONWARNINGS = $__prev_PYTHONWARNINGS
} else {
    Remove-Item env:PYTHONWARNINGS -ErrorAction SilentlyContinue
}
if ($null -ne $__prev_PYTHONUNBUFFERED) {
    $env:PYTHONUNBUFFERED = $__prev_PYTHONUNBUFFERED
} else {
    Remove-Item env:PYTHONUNBUFFERED -ErrorAction SilentlyContinue
}
if ($null -ne $__prev_PYTHONIOENCODING) {
    $env:PYTHONIOENCODING = $__prev_PYTHONIOENCODING
} else {
    Remove-Item env:PYTHONIOENCODING -ErrorAction SilentlyContinue
}

Write-Output "Workflow finished. Results: task3_benchmark.csv, task3_benchmark_summary.pptx"
