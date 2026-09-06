# Not required to run the app
# Generates the weights in Media.xcassets used to derank common classification predictions

#!/usr/bin/env python3
"""
Derive per-label deranking weights from a Swift classification log.

Explicit assumptions:
- A label is considered exposed if it appears in the top K predictions.
- A label is considered selected if selectedWords.originLabel matches it.
- Labels that are exposed often but rarely selected should be downweighted.
- Unseen labels are neutral (weight = 1.0).
- We only derank, never boost.

Output:
- weights.json written next to this script.
"""

import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Any, List, Tuple


# -----------------------
# Parameters (explicit)
# -----------------------

TOP_K = 10
M = 12.0
MIN_WEIGHT = 0.3


# -----------------------
# Helpers
# -----------------------

def clamp(x: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, x))


def top_k_labels(entry: Dict[str, Any], k: int) -> List[str]:
    items = entry.get("allClassifications", [])
    rows: List[Tuple[float, str]] = []

    for it in items:
        if not isinstance(it, dict):
            continue
        if it.get("wasFiltered", False):
            continue

        label = it.get("label")
        confidence = it.get("confidence")

        if isinstance(label, str) and isinstance(confidence, (int, float)):
            rows.append((float(confidence), label))

    rows.sort(key=lambda x: x[0], reverse=True)
    return [label for _, label in rows[:k]]


def selected_origin_labels(entry: Dict[str, Any]) -> List[str]:
    selected = entry.get("selectedWords", [])
    out: List[str] = []

    for w in selected:
        if not isinstance(w, dict):
            continue
        origin = w.get("originLabel")
        if isinstance(origin, str):
            out.append(origin)

    return out


# -----------------------
# Core logic
# -----------------------

def derive_weights(log_entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    exposed = Counter()   # n[L]
    picked = Counter()    # y[L]

    for entry in log_entries:
        labels = top_k_labels(entry, TOP_K)
        if not labels:
            continue

        exposed.update(labels)

        selected = set(selected_origin_labels(entry))
        for label in labels:
            if label in selected:
                picked[label] += 1

    total_exposed = sum(exposed.values())
    total_picked = sum(picked.values())

    if total_exposed == 0:
        raise ValueError("No exposed labels found in log")

    global_pick_rate = total_picked / total_exposed

    weights: Dict[str, float] = {}

    if global_pick_rate == 0.0:
        for label in exposed:
            weights[label] = 1.0
    else:
        for label, n in exposed.items():
            y = picked.get(label, 0)

            p_hat = (y + global_pick_rate * M) / (n + M)
            weight = clamp(p_hat / global_pick_rate, MIN_WEIGHT, 1.0)

            weights[label] = weight

    return {
        "meta": {
            "generatedAt": datetime.now(timezone.utc)
            .isoformat()
            .replace("+00:00", "Z"),
            "method": "smoothed-pick-rate-deranking",
            "parameters": {
                "topK": TOP_K,
                "smoothingM": M,
                "minWeight": MIN_WEIGHT,
            },
            "stats": {
                "totalExposures": total_exposed,
                "totalSelections": total_picked,
                "globalPickRate": global_pick_rate,
            },
        },
        "weights": weights,
    }


# -----------------------
# Entry point
# -----------------------

if __name__ == "__main__":
    import sys

    if len(sys.argv) != 2:
        print("Usage: python derive_weights.py log.json")
        sys.exit(1)

    log_path = Path(sys.argv[1])
    with log_path.open("r", encoding="utf-8") as f:
        log_data = json.load(f)

    result = derive_weights(log_data)

    out_path = Path(__file__).parent / "weights.json"
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, sort_keys=True)
        f.write("\n")

    print(f"Wrote weights to {out_path}")
