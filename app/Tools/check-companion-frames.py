#!/usr/bin/env python3
"""Compare adjacent REAL video frames for Anya appearance jumps outside her eyes.

Exit 1 = at least one unexplained appearance-jump candidate; 0 = none; 2 = input error.
Default coordinates apply to the supplied 645 x 1398, 30 fps recordings. The test
permits a +/- 4 px rigid translation before measuring appearance differences.
The fixed failure rule is residual mean RGB change >= 6/255 AND at least 12% of
the non-eye ROI changing by > 20/255 in one frame. It detects appearance jumps,
not their software cause; normal eye blinking and small breathing translations
are deliberately excluded. Never compare recordings with different UI layouts.
"""
from __future__ import annotations
import argparse
import csv
import json
from pathlib import Path
import re
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont


def box(value):
    result = tuple(int(v) for v in value.split(','))
    if len(result) != 4 or result[0] >= result[2] or result[1] >= result[3]:
        raise argparse.ArgumentTypeError('Use left,top,right,bottom')
    return result


def font(size):
    for path in ['/System/Library/Fonts/Supplemental/Arial.ttf', '/Library/Fonts/Arial.ttf']:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def numbered(path):
    found = re.search(r'(\d+)(?=\.png$)', path.name)
    if not found:
        raise ValueError(f'Frame filename must end in a number: {path}')
    return int(found.group(1))


def measure(previous, current, mask, radius):
    h, w = mask.shape
    m = radius
    core = np.s_[m:h-m, m:w-m]
    current_core = current[core]
    current_mask = mask[core]
    # Search on 2px samples, then measure the winning translation at full resolution.
    # A union of the two eye masks keeps blink pixels out even after alignment.
    gray_previous = previous @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    gray_current = current @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    best = None
    for dy in range(-m, m + 1):
        for dx in range(-m, m + 1):
            region = np.s_[m+dy:h-m+dy, m+dx:w-m+dx]
            valid = (current_mask & mask[region])[::2, ::2]
            error = np.abs(gray_current[core][::2, ::2] - gray_previous[region][::2, ::2])
            score = float(error[valid].mean())
            candidate = (score, abs(dx)+abs(dy), dx, dy)
            if best is None or candidate < best:
                best = candidate
    _, _, dx, dy = best
    region = np.s_[m+dy:h-m+dy, m+dx:w-m+dx]
    valid = current_mask & mask[region]
    residual = np.abs(current_core - previous[region]).mean(axis=2)
    raw = np.abs(current - previous).mean(axis=2)
    delta = (current_core - previous[region]) @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    values = {
        'raw_mae': float(raw[mask].mean()),
        'raw_changed_fraction': float((raw[mask] > 20).mean()),
        'aligned_mae': float(residual[valid].mean()),
        'aligned_changed_fraction': float((residual[valid] > 20).mean()),
        'signed_luma_change': float(delta[valid].mean()),
        'alignment_dx': dx, 'alignment_dy': dy,
    }
    heat = np.zeros((h, w), np.float32)
    heat[core] = np.where(valid, residual, 0)
    return values, heat


def evidence(paths, pair_index, metrics, heat, args):
    previous = Image.open(paths[pair_index-1]).convert('RGB')
    current = Image.open(paths[pair_index]).convert('RGB')
    scale = 3
    left, top, right, bottom = args.roi
    cw, ch = (right-left)*scale, (bottom-top)*scale
    sheet = Image.new('RGB', (cw*3+80, ch+146), '#F6F0E2')
    draw = ImageDraw.Draw(sheet)
    draw.text((20, 12), 'REAL VIDEO: strongest aligned adjacent-frame appearance jump', fill='#16382F', font=font(22))
    draw.text((20, 43), f"t={(pair_index-1)/args.fps:.3f}s -> {pair_index/args.fps:.3f}s | "
              f"mean {metrics['aligned_mae']:.2f}/255 | changed {metrics['aligned_changed_fraction']:.1%} | "
              f"align ({metrics['alignment_dx']:+d},{metrics['alignment_dy']:+d}) px", fill='#16382F', font=font(19))
    # This difference panel comes directly from compensated pixel differences.
    heat_rgb = np.stack([np.minimum(heat*5, 255), np.minimum(heat, 180), np.minimum(heat*.4, 80)], axis=2).astype(np.uint8)
    panels = [previous.crop(args.roi), current.crop(args.roi), Image.fromarray(heat_rgb)]
    names = [paths[pair_index-1].name, paths[pair_index].name, 'Aligned |difference| x5; eyes excluded']
    for i, (panel, title) in enumerate(zip(panels, names)):
        x = 20 + i*(cw+20)
        sheet.paste(panel.resize((cw, ch), Image.Resampling.NEAREST), (x, 108))
        draw.text((x, 82), title, fill='#16382F', font=font(17))
        if i < 2:
            ex1, ey1, ex2, ey2 = args.eyes
            draw.rectangle((x+(ex1-left)*scale, 108+(ey1-top)*scale,
                            x+(ex2-left)*scale, 108+(ey2-top)*scale), outline='#1E8B87', width=2)
    sheet.save(args.out/'worst-pair.png')
    context = Image.new('RGB', (previous.width*2+40, previous.height+60), '#F6F0E2')
    cd = ImageDraw.Draw(context)
    for i, im in enumerate([previous, current]):
        x = i*(previous.width+20)
        context.paste(im, (x, 60))
        cd.text((x+12, 12), names[i], fill='#16382F', font=font(24))
        cd.rectangle((x+left, 60+top, x+right, 60+bottom), outline='#C0604A', width=3)
    context.save(args.out/'worst-context.png')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('frames', type=Path, help='Directory containing consecutive frame-0001.png etc.')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--fps', type=float, default=30)
    parser.add_argument('--roi', type=box, default=(200,575,440,820))
    parser.add_argument('--eyes', type=box, default=(255,675,375,741))
    parser.add_argument('--translation-radius', type=int, default=4)
    parser.add_argument('--mean-threshold', type=float, default=6)
    parser.add_argument('--fraction-threshold', type=float, default=.12)
    args = parser.parse_args()
    paths = sorted(args.frames.glob('frame-*.png'), key=numbered)
    if len(paths) < 2:
        raise ValueError('Need at least two extracted real video frames')
    if any(numbered(b) != numbered(a)+1 for a,b in zip(paths, paths[1:])):
        raise ValueError('Frames are not consecutively numbered')
    size = Image.open(paths[0]).size
    x1,y1,x2,y2 = args.roi
    if not (0 <= x1 < x2 <= size[0] and 0 <= y1 < y2 <= size[1]):
        raise ValueError(f'ROI {args.roi} exceeds frame dimensions {size}')
    mask = np.ones((y2-y1, x2-x1), bool)
    ex1,ey1,ex2,ey2 = args.eyes
    if not (x1 <= ex1 < ex2 <= x2 and y1 <= ey1 < ey2 <= y2):
        raise ValueError('Eye box must lie within ROI')
    mask[ey1-y1:ey2-y1, ex1-x1:ex2-x1] = False
    args.out.mkdir(parents=True, exist_ok=True)
    def read(path):
        with Image.open(path) as image:
            if image.size != size:
                raise ValueError(f'Inconsistent frame dimensions: {path}')
            return np.array(image.convert('RGB').crop(args.roi), dtype=np.float32)
    previous = read(paths[0])
    rows, worst = [], None
    for i, path in enumerate(paths[1:], 1):
        current = read(path)
        row, heat = measure(previous, current, mask, args.translation_radius)
        row.update(previous=paths[i-1].name, current=path.name,
                   previous_time=(i-1)/args.fps, current_time=i/args.fps)
        row['flagged'] = row['aligned_mae'] >= args.mean_threshold and row['aligned_changed_fraction'] >= args.fraction_threshold
        rows.append(row)
        score = row['aligned_mae']
        if worst is None or score > worst[0]:
            worst = (score, i, row, heat.copy())
        previous = current
    with (args.out/'pairs.csv').open('w', newline='') as file:
        writer = csv.DictWriter(file, fieldnames=rows[0].keys())
        writer.writeheader(); writer.writerows(rows)
    summary = {
        'result': 'RED' if any(r['flagged'] for r in rows) else 'GREEN',
        'meaning': 'appearance-jump candidates outside the eyes after bounded translation compensation; does not identify cause',
        'input': str(args.frames.resolve()), 'frames': len(paths), 'fps': args.fps,
        'dimensions': list(size), 'roi': list(args.roi), 'excluded_eyes': list(args.eyes),
        'allowed_translation_px': args.translation_radius,
        'fixed_failure_rule': {'aligned_mean_rgb_at_least': args.mean_threshold,
                               'fraction_above_20_rgb_at_least': args.fraction_threshold},
        'flagged_pairs': sum(r['flagged'] for r in rows),
        'median_raw_mae': float(np.median([r['raw_mae'] for r in rows])),
        'median_aligned_mae': float(np.median([r['aligned_mae'] for r in rows])),
        'p95_aligned_mae': float(np.percentile([r['aligned_mae'] for r in rows], 95)),
        'worst_pair': worst[2],
        'top_pairs': sorted(rows, key=lambda r: r['aligned_mae'], reverse=True)[:12],
    }
    (args.out/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    evidence(paths, worst[1], worst[2], worst[3], args)
    print(json.dumps({k:v for k,v in summary.items() if k != 'top_pairs'}, indent=2))
    return 1 if summary['result'] == 'RED' else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError) as error:
        print(f'INPUT ERROR: {error}', file=sys.stderr)
        sys.exit(2)
