#!/usr/bin/env python3
"""
Score an existing placement.csv produced by place_cores.py.

For each tile prints SA cost, random-baseline cost, lower bound,
per-edge mean, and top longest edges. Writes per-tile and super-grid
PPM images colored by branch.

Usage:
  python3 score_placement.py bvh_nodes.txt leaf_core_roots_78pct.txt grid/placement.csv grid/
"""

import csv
import math
import random
import sys
from pathlib import Path

TREE_ROOT = 0
TILE      = 32
TILES_PER_ROW = 4
TILES_PER_COL = 2
SUPER_W   = TILE * TILES_PER_ROW
SUPER_H   = TILE * TILES_PER_COL
RNG_SEED  = 12345
N_RANDOM_TRIALS = 5


def parse_bvh(path):
    children = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) < 9:
                continue
            nid  = int(parts[0])
            lf   = int(parts[7])
            tc   = int(parts[8])
            children[nid] = None if tc != 0 else (lf, lf + 1)
    return children


def parse_leaves(path):
    out = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            out.append(int(line.split()[0]))
    return out


def left_to_right_branch_order(branch_set, children, root=TREE_ROOT):
    order = []
    stack = [root]
    while stack:
        n = stack.pop()
        if n in branch_set:
            order.append(n)
            continue
        kids = children.get(n)
        if kids is None:
            continue
        stack.append(kids[1])
        stack.append(kids[0])
    return order


def owners_one_pass(children, branch_set, leaf_set, root=TREE_ROOT):
    owner = {}
    leaves_by_branch = {b: [] for b in branch_set}
    ENTER, LEAVE = 0, 1
    stack = [(ENTER, root, None)]
    cur = None
    while stack:
        action, n, payload = stack.pop()
        if action == LEAVE:
            cur = payload
            continue
        if n in branch_set:
            stack.append((LEAVE, n, cur))
            cur = n
        if n in leaf_set and cur is not None:
            owner[n] = cur
            leaves_by_branch[cur].append(n)
        kids = children.get(n)
        if kids is not None:
            stack.append((ENTER, kids[1], None))
            stack.append((ENTER, kids[0], None))
    return owner, leaves_by_branch


def load_placement(csv_path):
    pos, kind, group, cell_to_node = {}, {}, {}, {}
    with open(csv_path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row["kind"] == "empty":
                continue
            nid = int(row["node_id"])
            x   = int(row["x"])
            y   = int(row["y"])
            pos[nid] = (x, y)
            kind[nid] = row["kind"]
            group[nid] = int(row["group"])
            cell_to_node[(x, y)] = nid
    return pos, kind, group, cell_to_node


def build_edges(group_branches_by_gi, leaves_by_branch_by_gi,
                global_leaf_order):
    edges_by_gi = {}
    for gi, gbranches in group_branches_by_gi.items():
        leaves_local = []
        for b in gbranches:
            leaves_local.extend(leaves_by_branch_by_gi[gi][b])
        leaf_set_local = set(leaves_local)

        edges = []
        for b in gbranches:
            for lf in leaves_by_branch_by_gi[gi][b]:
                a, c = (b, lf) if b < lf else (lf, b)
                edges.append((a, c))
        chain_local = [lf for lf in global_leaf_order if lf in leaf_set_local]
        for i in range(len(chain_local) - 1):
            a, b = chain_local[i], chain_local[i + 1]
            if a > b:
                a, b = b, a
            edges.append((a, b))
        edges_by_gi[gi] = edges
    return edges_by_gi


def manhattan(a, b):
    return abs(a[0] - b[0]) + abs(a[1] - b[1])


def edge_cost(edges, pos):
    return sum(manhattan(pos[u], pos[v]) for u, v in edges
               if u in pos and v in pos)


def random_baseline(node_ids, edges, side, rng, n_trials=5):
    cells = [(x, y) for y in range(side) for x in range(side)]
    totals = []
    for _ in range(n_trials):
        order = list(cells)
        rng.shuffle(order)
        pos = {nid: order[i] for i, nid in enumerate(node_ids)}
        totals.append(edge_cost(edges, pos))
    return sum(totals) / len(totals)


def lower_bound(edges, node_ids):
    deg = {n: 0 for n in node_ids}
    for u, v in edges:
        deg[u] += 1
        deg[v] += 1
    max_d = max(deg.values()) if deg else 0
    nearest = []
    if max_d > 0:
        radius = 1
        while len(nearest) < max_d:
            for dx in range(-radius, radius + 1):
                dy_abs = radius - abs(dx)
                opts = (dy_abs, -dy_abs) if dy_abs > 0 else (0,)
                for dy in opts:
                    nearest.append(abs(dx) + abs(dy))
            radius += 1
        nearest.sort()
        nearest = nearest[:max_d]
    total = 0
    for n in node_ids:
        d = deg[n]
        total += sum(nearest[:d])
    return total // 2


def top_long_edges(edges, pos, k=10):
    scored = [(manhattan(pos[u], pos[v]), u, v)
              for u, v in edges if u in pos and v in pos]
    scored.sort(reverse=True)
    return scored[:k]


def color_for_branch(b, branches_in_group):
    try:
        idx = branches_in_group.index(b)
    except ValueError:
        idx = 0
    h = (idx * 0.61803398875) % 1.0
    s, v = 0.65, 0.95
    i = int(h * 6)
    f = h * 6 - i
    p = v * (1 - s)
    q = v * (1 - f * s)
    t = v * (1 - (1 - f) * s)
    i %= 6
    if   i == 0: r, g, b_ = v, t, p
    elif i == 1: r, g, b_ = q, v, p
    elif i == 2: r, g, b_ = p, v, t
    elif i == 3: r, g, b_ = p, q, v
    elif i == 4: r, g, b_ = t, p, v
    else:        r, g, b_ = v, p, q
    return int(r * 255), int(g * 255), int(b_ * 255)


def write_ppm(path, w, h, pixels, scale=10):
    sw, sh = w * scale, h * scale
    with open(path, "wb") as f:
        f.write(f"P6\n{sw} {sh}\n255\n".encode())
        for sy in range(sh):
            y = sy // scale
            row = bytearray()
            for sx in range(sw):
                x = sx // scale
                r, g, b = pixels[y * w + x]
                row.extend((r, g, b))
            f.write(bytes(row))


def render_tile(out_path, side, group_branches, owner_of, pos,
                branches_set, kind):
    pixels = [(20, 20, 20)] * (side * side)
    for nid, (x, y) in pos.items():
        if nid in branches_set:
            b = nid
        else:
            b = owner_of.get(nid)
        if b is None:
            color = (60, 60, 60)
        else:
            color = color_for_branch(b, group_branches)
            if nid in branches_set:
                color = tuple(c // 2 + 32 for c in color)
        pixels[y * side + x] = color
    write_ppm(out_path, side, side, pixels, scale=10)


def render_super(out_path, w, h, cell_to_node, owner_of, branches_set,
                 group_branches_by_gi, group_of_node):
    pixels = [(15, 15, 15)] * (w * h)
    for (x, y), nid in cell_to_node.items():
        if nid in branches_set:
            b = nid
        else:
            b = owner_of.get(nid)
        gi = group_of_node.get(nid, -1)
        if b is None or gi < 0:
            color = (80, 80, 80)
        else:
            color = color_for_branch(b, group_branches_by_gi[gi])
            if nid in branches_set:
                color = tuple(c // 2 + 32 for c in color)
        pixels[y * w + x] = color
    write_ppm(out_path, w, h, pixels, scale=6)


def main():
    if len(sys.argv) < 6:
        print("usage: score_placement.py bvh_nodes.txt leaf_core_roots.txt "
              "branch_core_roots.txt placement.csv out_dir/", file=sys.stderr)
        sys.exit(1)
    bvh_path, leaf_path, branch_path, csv_path, out_dir = sys.argv[1:6]
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    print("Parsing BVH...")
    children     = parse_bvh(bvh_path)
    leaves       = parse_leaves(leaf_path)
    branch_roots = parse_leaves(branch_path)   # same one-int-per-line format
    leaf_set     = set(leaves)
    branch_set   = set(branch_roots)

    print("Computing branch DFS order + owner assignment...")
    branch_order = left_to_right_branch_order(branch_set, children)
    owner, leaves_by_branch = owners_one_pass(children, branch_set, leaf_set)

    print("Loading placement...")
    pos, kind, group, cell_to_node = load_placement(csv_path)

    group_branches_by_gi  = {}
    leaves_by_branch_by_gi = {}
    for nid, gi in group.items():
        if gi < 0:
            continue
        group_branches_by_gi.setdefault(gi, [])
        leaves_by_branch_by_gi.setdefault(gi, {})
    for b in branch_roots:
        gi = group.get(b)
        if gi is None or gi < 0:
            continue
        group_branches_by_gi[gi].append(b)
        leaves_by_branch_by_gi[gi].setdefault(b, [])
    for gi in group_branches_by_gi:
        gset = set(group_branches_by_gi[gi])
        group_branches_by_gi[gi] = [b for b in branch_order if b in gset]

    for lf, b in owner.items():
        gi_lf = group.get(lf)
        gi_b  = group.get(b)
        if gi_lf is None or gi_lf < 0:
            continue
        if gi_lf != gi_b:
            continue
        leaves_by_branch_by_gi[gi_lf].setdefault(b, []).append(lf)

    global_leaf_order = []
    for b in branch_order:
        global_leaf_order.extend(leaves_by_branch[b])
    leaf_dfs_index = {lf: i for i, lf in enumerate(global_leaf_order)}
    for gi, by_b in leaves_by_branch_by_gi.items():
        for b in by_b:
            by_b[b] = sorted(by_b[b], key=lambda x: leaf_dfs_index.get(x, 0))

    edges_by_gi = build_edges(group_branches_by_gi, leaves_by_branch_by_gi,
                              global_leaf_order)

    rng = random.Random(RNG_SEED)
    lines = []
    grand_real = 0
    grand_random = 0.0
    grand_lb = 0
    grand_edges = 0

    for gi in sorted(group_branches_by_gi):
        gbranches = group_branches_by_gi[gi]
        leaves_in_gi = [lf for b in gbranches
                        for lf in leaves_by_branch_by_gi[gi][b]]
        node_ids = list(gbranches) + leaves_in_gi
        edges = edges_by_gi[gi]

        real_cost = edge_cost(edges, pos)
        rand_cost = random_baseline(node_ids, edges, TILE, rng,
                                    N_RANDOM_TRIALS)
        lb        = lower_bound(edges, node_ids)
        per_edge  = real_cost / len(edges) if edges else 0.0
        ratio     = real_cost / rand_cost if rand_cost else float("nan")
        gap       = real_cost / lb if lb else float("nan")

        msg = (f"group {gi}: {len(node_ids):4d} nodes, "
               f"{len(edges):4d} edges, "
               f"SA={real_cost:6d}  random={rand_cost:8.0f}  "
               f"LB={lb:6d}  per-edge={per_edge:5.2f}  "
               f"vs-random={ratio:5.2f}x  vs-LB={gap:5.2f}x")
        print(msg)
        lines.append(msg)

        longest = top_long_edges(edges, pos, k=5)
        lines.append(f"  top 5 longest edges (dist, u, v):")
        for d, u, v in longest:
            lines.append(f"    {d:3d}  {u}  {v}")

        tile_row = gi // TILES_PER_ROW
        if tile_row == 0:
            tile_col = gi % TILES_PER_ROW
        else:
            tile_col = (TILES_PER_ROW - 1) - (gi % TILES_PER_ROW)
        ox = tile_col * TILE
        oy = tile_row * TILE
        tile_pos = {}
        for nid in node_ids:
            if nid not in pos:
                continue
            lx = pos[nid][0] - ox
            ly = pos[nid][1] - oy
            if tile_row == 1:
                lx = (TILE - 1) - lx        # un-mirror for the per-tile image
            tile_pos[nid] = (lx, ly)
        render_tile(out_dir / f"tile_{gi}.ppm", TILE,
                    gbranches, owner, tile_pos, branch_set, kind)

        grand_real   += real_cost
        grand_random += rand_cost
        grand_lb     += lb
        grand_edges  += len(edges)

    msg = (f"\nTOTAL: SA={grand_real}  random={grand_random:.0f}  "
           f"LB={grand_lb}  edges={grand_edges}  "
           f"vs-random={grand_real/grand_random:.2f}x  "
           f"vs-LB={grand_real/grand_lb:.2f}x")
    print(msg)
    lines.append(msg)

    render_super(out_dir / "super.ppm", SUPER_W, SUPER_H, cell_to_node,
                 owner, branch_set, group_branches_by_gi, group)

    (out_dir / "score.txt").write_text("\n".join(lines) + "\n")
    print(f"\nWrote {out_dir/'score.txt'}, "
          f"tile_*.ppm and super.ppm in {out_dir}")
    print("(PPM files open in IrfanView, GIMP, or VSCode's PPM extension; "
          "or convert: `magick super.ppm super.png`)")


if __name__ == "__main__":
    main()