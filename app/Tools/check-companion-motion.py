"""Measure eye-line roll in the shipped assets against the real motion model.

Read-only image analysis. The JSON samples come from check-companion-motion.swift,
compiled with the same CompanionMotion.swift source used by the app.
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def source_roll(character):
    prefix = character.title()
    path = ROOT / f"LifeOS/Resources/Assets.xcassets/CompanionRigs/{prefix}RigHead.imageset/{character}-head.png"
    pixels = np.asarray(Image.open(path)).astype(float)
    r, g, b, alpha = pixels.transpose(2, 0, 1)
    if character == "anya":
        mask = (g > r * 1.13) & (g > b * 1.15) & (g > 40) & (alpha > 200)
        top, bottom, spans = 380, 520, [(230, 375), (375, 520)]
        weights = np.maximum(0, g - r - b * 0.05)
    else:
        mask = (r > g * 1.8) & (r > b * 1.3) & (r > 55) & (alpha > 200)
        top, bottom, spans = 260, 345, [(205, 316), (316, 430)]
        weights = r - g
    centers = []
    for left, right in spans:
        region = mask[top:bottom, left:right]
        yy, xx = np.where(region)
        if len(xx) < 100:
            raise ValueError(f"{character}: cannot identify both irises")
        weight = weights[top:bottom, left:right][region]
        centers.append((float(np.average(xx + left, weights=weight)),
                        float(np.average(yy + top, weights=weight))))
    dx = centers[1][0] - centers[0][0]
    dy = centers[1][1] - centers[0][1]
    return math.degrees(math.atan2(dy, dx))


samples = json.loads(Path(sys.argv[1]).read_text())
results = []
for sample in samples:
    angle = source_roll(sample["character"])
    worst = max(abs(angle + sample["minimumAngle"]), abs(angle + sample["maximumAngle"]))
    passed = worst <= 1.0
    results.append({**sample, "sourceRoll": angle, "worstEyeLineRoll": worst, "passed": passed})
    print(f'{"PASS" if passed else "FAIL"} {sample["character"]}/{sample["mood"]}: eye-line roll ≤ {worst:.3f}° (limit 1°)')
if len(sys.argv) > 2:
    Path(sys.argv[2]).write_text(json.dumps(results, indent=2) + "\n")
sys.exit(0 if all(result["passed"] for result in results) else 1)
