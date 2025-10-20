#!/usr/bin/env bash
set -e

# ==== Parâmetros de carga (ajuste se quiser) ====
DUR="${DUR:-45s}"
THREADS="${THREADS:-32}"
CONN="${CONN:-128}"
Q="${Q:-allocBytes=4000000&cpuIters=200000&burstMs=50&sleepMs=5&payloadKb=1}"
N="${N:-300}"   # usado no fallback via curl

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"
OUT_LAT="$ROOT/out/lat"; mkdir -p "$OUT_LAT"

ts() { date +%Y%m%d-%H%M%S; }
has_wrk() { command -v wrk >/dev/null 2>&1; }
has_docker() { command -v docker >/dev/null 2>&1; }

# ==== Alvos (3 instâncias via compose) ====
URL_G1="http://localhost:8081/work?$Q"
URL_ZGC="http://localhost:8082/work?$Q"
URL_SHEN="http://localhost:8083/work?$Q"

# ==== LUA p/ resumir o wrk em JSON ====
WRK_LUA="$OUT_LAT/wrk_summary.lua"
cat > "$WRK_LUA" <<'LUA'
done = function(summary, latency, requests)
  io.write(string.format('{ "req_per_sec": %.2f, "p50_ms": %.2f, "p95_ms": %.2f, "p99_ms": %.2f, "errors": %d }\n',
    summary.requests/summary.duration*1e6,
    latency:percentile(50.0)/1000.0,
    latency:percentile(95.0)/1000.0,
    latency:percentile(99.0)/1000.0,
    summary.errors.status + summary.errors.connect + summary.errors.read + summary.errors.write))
end
LUA

# ==== Execução com wrk local ====
run_wrk_local() {
  local name="$1" url="$2"
  local raw="$OUT_LAT/${name}-$(ts).raw"
  local jsn="${raw%.raw}.json"
  echo "→ $name (wrk local): $url  DUR=$DUR T=$THREADS C=$CONN"
  wrk -t"$THREADS" -c"$CONN" -d"$DUR" -s "$WRK_LUA" "$url" | tee "$raw"
  # extrai somente a última linha que começa com "{"
  grep -a '{' "$raw" | tail -n1 > "$jsn"
}


# ==== Execução com wrk em Docker ====
# Nota: Em Docker Desktop (Windows/macOS), use host.docker.internal para atingir as portas 8081/8082/8083 no host.
to_docker_url() {
  case "$1" in
    http://localhost:8081/*) echo "$1" | sed 's|http://localhost:8081/|http://host.docker.internal:8081/|';;
    http://localhost:8082/*) echo "$1" | sed 's|http://localhost:8082/|http://host.docker.internal:8082/|';;
    http://localhost:8083/*) echo "$1" | sed 's|http://localhost:8083/|http://host.docker.internal:8083/|';;
    *) echo "$1";;
  esac
}

run_wrk_docker() {
  local name="$1" url="$2"
  local durl; durl="$(to_docker_url "$url")"
  local raw="$OUT_LAT/${name}-$(ts).raw"
  local jsn="${raw%.raw}.json"
  echo "→ $name (wrk em Docker): $durl  DUR=$DUR T=$THREADS C=$CONN"
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL="*" \
  docker run --rm \
    -v "$OUT_LAT":/wrk \
    --add-host=host.docker.internal:host-gateway \
    williamyeh/wrk \
      -t"$THREADS" -c"$CONN" -d"$DUR" -s /wrk/wrk_summary.lua "$durl" | tee "$raw"
  grep -a '{' "$raw" | tail -n1 > "$jsn"
}


# ==== Fallback com curl (p50/p95/p99 + req/s aproximado) ====
run_curl_fallback() {
  local name="$1" url="$2" out_json="$OUT_LAT/${name}-$(ts).json"
  local tmp="$OUT_LAT/${name}-lat-ms.txt"
  echo "→ $name (curl fallback): $url  N=$N"
  : > "$tmp"
  for i in $(seq 1 "$N"); do
    # mede tempo total da requisição em segundos e grava em ms (3 casas)
    curl -s -o /dev/null -w '%{time_total}\n' "$url" | awk '{printf "%.3f\n",$1*1000}' >> "$tmp"
  done
  sort -n -o "$tmp" "$tmp"
  local total; total=$(wc -l < "$tmp")
  p() { awk -v n="$total" -v p="$1" 'BEGIN{i=int(n*p/100); if(i<1)i=1; print i}' ;}
  local p50_idx; p50_idx=$(p 50)
  local p95_idx; p95_idx=$(p 95)
  local p99_idx; p99_idx=$(p 99)
  local p50; p50=$(awk "NR==$p50_idx{print; exit}" "$tmp")
  local p95; p95=$(awk "NR==$p95_idx{print; exit}" "$tmp")
  local p99; p99=$(awk "NR==$p99_idx{print; exit}" "$tmp")
  local avg_ms; avg_ms=$(awk '{s+=$1}END{if(NR>0)printf "%.3f", s/NR; else print "0.000"}' "$tmp")
  local rps; rps=$(awk -v a="$avg_ms" 'BEGIN{if(a>0)printf "%.2f", 1000.0/a; else print "0.00"}')
  echo "{ \"req_per_sec\": $rps, \"p50_ms\": $p50, \"p95_ms\": $p95, \"p99_ms\": $p99, \"errors\": 0 }" | tee "$out_json"
}

main() {
  if has_wrk; then
    run_wrk_local "g1"   "$URL_G1"   &
    run_wrk_local "zgc"  "$URL_ZGC"  &
    run_wrk_local "shen" "$URL_SHEN" &
    wait
  elif has_docker; then
    # tenta usar wrk via docker
    if docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -q '^williamyeh/wrk:' || docker pull williamyeh/wrk >/dev/null 2>&1; then
      run_wrk_docker "g1"   "$URL_G1"   &
      run_wrk_docker "zgc"  "$URL_ZGC"  &
      run_wrk_docker "shen" "$URL_SHEN" &
      wait
    else
      echo "Não consegui puxar a imagem williamyeh/wrk. Indo de curl fallback."
      run_curl_fallback "g1"   "$URL_G1"   &
      run_curl_fallback "zgc"  "$URL_ZGC"  &
      run_curl_fallback "shen" "$URL_SHEN" &
      wait
    fi
  else
    echo "Docker não encontrado e wrk não instalado — usando curl fallback."
    run_curl_fallback "g1"   "$URL_G1"   &
    run_curl_fallback "zgc"  "$URL_ZGC"  &
    run_curl_fallback "shen" "$URL_SHEN" &
    wait
  fi

  echo "✓ burst concluído — arquivos em: $OUT_LAT"
}
main "$@"
