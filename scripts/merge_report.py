#!/usr/bin/env python3
import os, json, csv, glob

ROOT = os.path.join(os.path.dirname(__file__), "..", "out")
LAT_DIR = os.path.join(ROOT, "lat")
GC_REPORT = os.path.join(ROOT, "gc_report.csv")
OUT_CSV = os.path.join(ROOT, "final_report.csv")

def key_from_gcname(gcname: str):
    gc = (gcname or "").lower()
    if "shen" in gc: return "shen"
    if "zgc" in gc:  return "zgc"
    if "g1" in gc:   return "g1"
    return None

# 1) latência
lat_results = {}
for f in glob.glob(os.path.join(LAT_DIR, "*.json")):
    name = os.path.basename(f).split("-")[0].lower()
    if name not in ("g1","zgc","shen"):
        continue
    try:
        with open(f, encoding="utf-8") as fh:
            d = json.load(fh)
        lat_results[name] = {
            "req_per_sec": d.get("req_per_sec"),
            "p50_ms": d.get("p50_ms"),
            "p95_ms": d.get("p95_ms"),
            "p99_ms": d.get("p99_ms"),
        }
    except Exception as e:
        print(f"[warn] falha lendo {f}: {e}")

# 2) GC report
gc_rows = {}
if os.path.exists(GC_REPORT):
    with open(GC_REPORT, encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        for r in reader:
            k = key_from_gcname(r.get("gc",""))
            if not k:
                base = os.path.basename(r.get("file","")).lower()
                if "shen" in base: k = "shen"
                elif "zgc" in base: k = "zgc"
                elif "g1"  in base: k = "g1"
            if not k:
                continue
            gc_rows[k] = {
                "collections": r.get("collections",""),
                "total_pause_ms": r.get("total_pause_ms",""),
                "max_pause_ms": r.get("max_pause_ms",""),
                "avg_pause_ms": r.get("avg_pause_ms",""),
            }

# 3) consolida
GCs = [gc for gc in ("g1","zgc","shen") if gc in set(list(lat_results.keys()) + list(gc_rows.keys()))]
if not GCs:
    print("Nenhum dado de g1/zgc/shen encontrado. Rode o burst e o parser de GC primeiro.")
    raise SystemExit(0)

rows = []
for gc in GCs:
    lat = lat_results.get(gc, {})
    gcm = gc_rows.get(gc, {})
    rows.append({
        "gc": gc.upper(),
        "req_per_sec": lat.get("req_per_sec", ""),
        "p50_ms": lat.get("p50_ms", ""),
        "p95_ms": lat.get("p95_ms", ""),
        "p99_ms": lat.get("p99_ms", ""),
        "collections": gcm.get("collections", ""),
        "total_pause_ms": gcm.get("total_pause_ms", ""),
        "max_pause_ms": gcm.get("max_pause_ms", ""),
        "avg_pause_ms": gcm.get("avg_pause_ms", ""),
    })

# 4) grava CSV
os.makedirs(os.path.dirname(OUT_CSV), exist_ok=True)
with open(OUT_CSV, "w", newline="", encoding="utf-8") as fh:
    writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    writer.writerows(rows)

print(f"Relatorio consolidado salvo em: {OUT_CSV}")
for r in rows:
    print(f" - {r['gc']:6s} | {r['req_per_sec']} req/s | p99={r['p99_ms']} ms | avgGC={r['avg_pause_ms']} ms")
