# Genera la evidencia obligatoria en evidence\ (equivalente PowerShell de capture_evidence.sh).
# Uso (desde la raíz del repo, con credenciales AWS activas):  .\scripts\capture_evidence.ps1
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

$out = "evidence"
New-Item -ItemType Directory -Force $out | Out-Null

$apiUrl = (terraform output -raw api_url).Trim()
$bucket = (terraform output -raw results_bucket).Trim()

# Payload único por ejecución: garantiza que la primera llamada sea MISS.
$runId = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$payload = '{"message":"evidencia","run_id":"' + $runId + '"}'
$tmp = Join-Path ([IO.Path]::GetTempPath()) "payload.json"
[IO.File]::WriteAllText($tmp, $payload)   # archivo sin BOM, evita problemas de comillas con curl

function Invoke-Call {
    curl.exe -sS -i -X POST $apiUrl -H "Content-Type: application/json" --data-binary "@$tmp"
}

$ts = (Get-Date).ToUniversalTime().ToString("s") + "Z"
$r1 = @("# $ts  POST $apiUrl", "# payload: $payload", "") + (Invoke-Call)
$r1 | Tee-Object -FilePath "$out\01_request_1_MISS.txt"

"`n-----"; Start-Sleep -Seconds 1

$ts = (Get-Date).ToUniversalTime().ToString("s") + "Z"
$r2 = @("# $ts  POST $apiUrl  (mismo payload)", "# payload: $payload", "") + (Invoke-Call)
$r2 | Tee-Object -FilePath "$out\02_request_2_HIT.txt"

"`n-----"

if (-not ($r1 -match '(?i)^x-cache:\s*MISS')) { throw "La 1a llamada no devolvio X-Cache: MISS" }
if (-not ($r2 -match '(?i)^x-cache:\s*HIT'))  { throw "La 2a llamada no devolvio X-Cache: HIT" }
"OK: MISS -> HIT verificado"

$s3 = @("# aws s3 ls s3://$bucket/results/ --recursive") + (aws s3 ls "s3://$bucket/results/" --recursive)
$s3 | Tee-Object -FilePath "$out\03_s3_ls.txt"
