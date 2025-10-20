#!/usr/bin/env python3
import sys, re, os, csv

root = sys.argv[1] if len(sys.argv)>1 else "out"

# Ex.: "... Pause Young (Normal) ... 1.234ms" em G1/ZGC/Shen
pat_pause = re.compile(r".*\bPause\b.*? ([0-9]+(?:\.[0-9]+)?)ms", re.IGNORECASE)
# Ex.: "[info][gc] Using Shenandoah" | "Using G1" | "Using ZGC"
pat_using = re.compile(r".*\bUsing\s+([A-Za-z0-9\-_]+)", re.IGNORECASE)

rows = []

for dirpath, _, files in os.walk(root):
    for f in files:
        if not f.endswith(".log"):
            continue
        path = os.path.join(dirpath, f)
        pauses = []
        using_gc = ""
        try:
            with open(path, "r", errors="ignore") as fh:
                for line in fh:
                    m = pat_pause.match(line.strip())
                    if m:
                        pauses.append(float(m.group(1)))
                    u = pat_using.match(line.strip())
                    if u:
                        using_gc = u.group(1)
        except Exception:
            continue

        # fallback: infere pelo nome do arquivo (gc-g1-..., gc-zgc-..., gc-shen-...)
        if not using_gc:
            base = os.path.basename(path).lower()
            if "shen" in base:
                using_gc = "Shenandoah"
            elif "zgc" in base:
                using_gc = "ZGC"
            elif "g1" in base:
                using_gc = "G1"
            else:
                using_gc = ""

        if pauses:
            total = sum(pauses)
            mx = max(pauses)
            avg = total / len(pauses)
            rows.append([path, using_gc, len(pauses), f"{total:.3f}", f"{mx:.3f}", f"{avg:.3f}"])

rows.sort(key=lambda r: r[0])

out_csv = os.path.join(root, "gc_report.csv")
os.makedirs(root, exist_ok=True)
with open(out_csv, "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["file","gc","collections","total_pause_ms","max_pause_ms","avg_pause_ms"])
    w.writerows(rows)

print(f"GC report -> {out_csv}")
