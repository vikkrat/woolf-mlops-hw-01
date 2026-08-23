<#
.SYNOPSIS
    PowerShell equivalent of scripts/collect_metrics.sh (for Windows without Git Bash / WSL).

.DESCRIPTION
    Exports the TorchScript model, builds both Docker images, runs inference in each,
    compares the results and writes every measurement to metrics.txt.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\collect_metrics.ps1
    powershell -ExecutionPolicy Bypass -File scripts\collect_metrics.ps1 -NoCache
#>
param(
    [switch]$NoCache
)

$ErrorActionPreference = "Continue"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

$MetricsFile = Join-Path $ProjectRoot "metrics.txt"
$FatImage    = "ml-infer-fat:1.0"
$SlimImage   = "ml-infer-slim:1.0"
$FatOut      = Join-Path $ProjectRoot "output_fat.txt"
$SlimOut     = Join-Path $ProjectRoot "output_slim.txt"
$BuildArgs   = @()
if ($NoCache) { $BuildArgs += "--no-cache" }

function Say([string]$Text) {
    Write-Host $Text
    Add-Content -Path $MetricsFile -Value $Text -Encoding UTF8
}
function Head([string]$Text) { Say ""; Say "=== $Text ===" }

Set-Content -Path $MetricsFile -Value "metrics collected: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Encoding UTF8
Say "host: $([System.Environment]::OSVersion.VersionString)"

docker info | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker daemon is not reachable. Start Docker Desktop and retry."
    exit 1
}
Say "docker: $(docker --version)"
Say "compose: $((docker compose version) -join ' ')"

# --- 1. model -------------------------------------------------------------
Head "1. MODEL EXPORT"
if (Test-Path "model\model.pt") {
    Say "model/model.pt already exists - skipping export (idempotent)"
} else {
    Say "exporting inside a python:3.13 container ..."
    docker run --rm -v "${PWD}:/w" -w /w python:3.13 `
        sh -c "pip install --no-cache-dir -q -r requirements.txt && python export_model.py" 2>&1 |
        ForEach-Object { Say $_ }
}
if (Test-Path "model\model.pt") {
    Say ("model file size: {0:N2} MB" -f ((Get-Item "model\model.pt").Length / 1MB))
}

# --- 2-3. builds ----------------------------------------------------------
function Build-Image([string]$Dockerfile, [string]$Tag) {
    Head "BUILD $Tag (-f $Dockerfile $($BuildArgs -join ' '))"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    docker build @BuildArgs -f $Dockerfile -t $Tag . | Out-Null
    $code = $LASTEXITCODE
    $sw.Stop()
    if ($code -eq 0) {
        Say "build status : OK"
        Say ("build time   : {0:N0} s" -f $sw.Elapsed.TotalSeconds)
    } else {
        Say ("build status : FAILED after {0:N0} s" -f $sw.Elapsed.TotalSeconds)
        Say "re-run manually to see the error: docker build -f $Dockerfile -t $Tag ."
    }
}

Build-Image "Dockerfile.fat"  $FatImage
Build-Image "Dockerfile.slim" $SlimImage

# --- 4. inference ---------------------------------------------------------
function Run-Inference([string]$Tag, [string]$OutFile) {
    Head "INFERENCE $Tag"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    docker run --rm -v "${PWD}\example.jpg:/app/example.jpg:ro" $Tag example.jpg 2>&1 |
        Out-File -FilePath $OutFile -Encoding UTF8
    $sw.Stop()
    Get-Content $OutFile | ForEach-Object { Say $_ }
    Say ("wall time    : {0:N0} ms" -f $sw.Elapsed.TotalMilliseconds)
}

Run-Inference $FatImage  $FatOut
Run-Inference $SlimImage $SlimOut

Head "INFERENCE DIFF (fat vs slim)"
$fatPred  = (Get-Content $FatOut  | Select-String "class_id") -join "`n"
$slimPred = (Get-Content $SlimOut | Select-String "class_id") -join "`n"
if ($fatPred -eq $slimPred -and $fatPred -ne "") {
    Say "IDENTICAL - top-3 predictions match bit for bit"
} else {
    Say "DIFFERENT - compare output_fat.txt and output_slim.txt"
}

# --- 5. image comparison --------------------------------------------------
Head "5. IMAGE SIZES"
docker images | Select-Object -First 1 | ForEach-Object { Say $_ }
docker images | Select-String "ml-infer" | ForEach-Object { Say $_.ToString() }

Head "5.1 LAYER COUNT"
foreach ($tag in @($FatImage, $SlimImage)) {
    $layers  = docker image inspect -f '{{len .RootFS.Layers}}' $tag
    $history = (docker history -q $tag | Measure-Object).Count
    Say "${tag}: $layers layers (rootfs), $history history entries"
}

Head "5.2 DOCKER HISTORY - FAT"
docker history --no-trunc --format 'table {{.Size}}\t{{.CreatedBy}}' $FatImage |
    ForEach-Object { Say ($_.Substring(0, [Math]::Min(160, $_.Length))) }

Head "5.3 DOCKER HISTORY - SLIM"
docker history --no-trunc --format 'table {{.Size}}\t{{.CreatedBy}}' $SlimImage |
    ForEach-Object { Say ($_.Substring(0, [Math]::Min(160, $_.Length))) }

Head "5.4 BASE IMAGE SIZES"
docker images | Select-String "^python " | ForEach-Object { Say $_.ToString() }

Head "5.5 WHAT IS INSIDE EACH IMAGE (/app)"
Say "--- fat /app:"
docker run --rm --entrypoint sh $FatImage -c "ls -la /app" 2>&1 | ForEach-Object { Say $_ }
Say "--- slim /app:"
docker run --rm --entrypoint sh $SlimImage -c "ls -la /app" 2>&1 | ForEach-Object { Say $_ }
Say "fat  gcc : $(docker run --rm --entrypoint sh $FatImage  -c 'command -v gcc || echo absent' 2>&1)"
Say "slim gcc : $(docker run --rm --entrypoint sh $SlimImage -c 'command -v gcc || echo absent' 2>&1)"

Head "DONE"
Say "all measurements saved to metrics.txt"
Say "inference outputs saved to output_fat.txt / output_slim.txt"
