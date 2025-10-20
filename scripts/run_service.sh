#!/usr/bin/env bash
set -euo pipefail

# No container, o script está em /app. Mantemos exatamente esse diretório.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"
cd "$ROOT"

req_gc="${GC:-zgc}"   # g1 | zgc | shen
heap="${HEAP:-2g}"

# Detecção robusta: tenta executar a flag do GC
gc_flag=""
case "$req_gc" in
  g1)   gc_flag="-XX:+UseG1GC" ;;
  zgc)  if java -XX:+UseZGC -version >/dev/null 2>&1; then
          gc_flag="-XX:+UseZGC"
        else
          echo "ZGC não suportado; fallback para G1..."
          gc_flag="-XX:+UseG1GC"
        fi ;;
  shen) if java -XX:+UseShenandoahGC -version >/dev/null 2>&1; then
          gc_flag="-XX:+UseShenandoahGC"
        else
          echo "Shenandoah não suportado; fallback para ZGC/G1..."
          if java -XX:+UseZGC -version >/dev/null 2>&1; then
            gc_flag="-XX:+UseZGC"
          else
            gc_flag="-XX:+UseG1GC"
          fi
        fi ;;
  *)    gc_flag="-XX:+UseZGC" ;;
esac

JAVA_OPTS="${JAVA_OPTS:-} -Xms${heap} -Xmx${heap} -XX:+AlwaysPreTouch ${gc_flag}"

# No container, temos /app/app.jar; fora do container, pode haver target/*.jar
JAR="app.jar"
if [[ ! -f "$JAR" ]]; then
  JAR=$(ls target/*.jar 2>/dev/null | head -n1 || true)
fi
if [[ -z "${JAR}" || ! -f "$JAR" ]]; then
  echo "Nenhum JAR encontrado (procurei app.jar e target/*.jar)"; exit 1
fi

echo "Iniciando: GC=${gc_flag#*-XX:+Use} HEAP=$heap JAR=$JAR"
exec java $JAVA_OPTS -jar "$JAR"
