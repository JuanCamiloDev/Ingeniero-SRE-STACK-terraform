#!/usr/bin/env bash
# Genera la evidencia obligatoria en evidence/ contra el stack ya desplegado:
#   01_request_1_MISS.txt  -> primera llamada (X-Cache: MISS)
#   02_request_2_HIT.txt   -> misma llamada repetida (X-Cache: HIT)
#   03_s3_ls.txt           -> objeto guardado en S3
# Uso (desde la raíz del repo, con credenciales AWS activas):  ./scripts/capture_evidence.sh
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="evidence"
mkdir -p "$OUT"

API_URL="$(terraform output -raw api_url)"
BUCKET="$(terraform output -raw results_bucket)"

# Payload único por ejecución: garantiza que la primera llamada sea MISS aunque ya corrieras la demo.
PAYLOAD="{\"message\":\"evidencia\",\"run_id\":\"$(date +%s)\"}"

call() {
  curl -sS -i -X POST "$API_URL" -H 'Content-Type: application/json' -d "$PAYLOAD"
}

{
  echo "# $(date -u +%FT%TZ)  POST $API_URL"
  echo "# payload: $PAYLOAD"
  echo
  call
} | tee "$OUT/01_request_1_MISS.txt"

echo; echo "-----"; sleep 1

{
  echo "# $(date -u +%FT%TZ)  POST $API_URL  (mismo payload)"
  echo "# payload: $PAYLOAD"
  echo
  call
} | tee "$OUT/02_request_2_HIT.txt"

echo; echo "-----"

grep -qi '^x-cache: MISS' "$OUT/01_request_1_MISS.txt" || { echo "ERROR: la 1a llamada no devolvió X-Cache: MISS"; exit 1; }
grep -qi '^x-cache: HIT'  "$OUT/02_request_2_HIT.txt"  || { echo "ERROR: la 2a llamada no devolvió X-Cache: HIT"; exit 1; }
echo "OK: MISS -> HIT verificado"

{
  echo "# aws s3 ls s3://$BUCKET/results/ --recursive"
  aws s3 ls "s3://$BUCKET/results/" --recursive
} | tee "$OUT/03_s3_ls.txt"
