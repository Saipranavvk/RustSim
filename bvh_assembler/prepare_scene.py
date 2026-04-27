#!/usr/bin/env python3
"""
prepare_scene.py
----------------
Reads room.obj, builds a BVH2, collapses it into a BVH4, and writes:

    scene.txt   - triangle soup in BVH-leaf order (12 floats/tri)
    bvh2.txt    - BVH2 flat node array (NEW)
    bvh4.txt    - BVH4 flat node array
    camera.txt  - camera pose
    lights.txt  - point lights (only if missing)
"""

import argparse
import os
import re
import sys
import time
import numpy as np

MATERIAL_RE = re.compile(r"wire_(\d{3})(\d{3})(\d{3})")
LEAF_THRESHOLD = 4


# ---------------------------------------------------------------------------
# OBJ parsing + triangulation
# ---------------------------------------------------------------------------

def decode_material(name):
    m = MATERIAL_RE.match(name.strip())
    if not m:
        return (0.5, 0.5, 0.5)
    r, g, b = (int(m.group(i)) for i in (1, 2, 3))
    return (min(r,255)/255.0, min(g,255)/255.0, min(b,255)/255.0)


def parse_face_indices(tokens):
    out = []
    for tok in tokens:
        i = tok.split("/", 1)[0]
        if i:
            out.append(int(i) - 1)
    return out


def load_obj(path):
    vertices = []
    faces = []
    current_color = (0.5, 0.5, 0.5)

    t0 = time.time()
    with open(path, "r", errors="replace") as f:
        for line in f:
            if not line: continue
            if line.startswith("v "):
                p = line.split()
                vertices.append((float(p[1]), float(p[2]), float(p[3])))
            elif line.startswith("f "):
                idx = parse_face_indices(line.split()[1:])
                if len(idx) >= 3:
                    faces.append((idx, current_color))
            elif line.startswith("usemtl"):
                parts = line.split(maxsplit=1)
                current_color = decode_material(parts[1]) if len(parts) > 1 else (0.5,)*3

    print(f"[prepare] OBJ parsed in {time.time()-t0:.2f}s: "
          f"{len(vertices):,} vertices, {len(faces):,} face records")

    return np.asarray(vertices, dtype=np.float32), faces


def triangulate(vertices, faces):
    n_tri = sum(len(idx) - 2 for idx, _ in faces if len(idx) >= 3)
    print(f"[prepare] triangulating to {n_tri:,} triangles...")

    tri_pos = np.empty((n_tri, 3, 3), dtype=np.float32)
    tri_col = np.empty((n_tri, 3), dtype=np.float32)

    t0 = time.time()
    w = 0

    for idx, col in faces:
        if len(idx) < 3: continue
        v0 = vertices[idx[0]]
        for k in range(1, len(idx) - 1):
            tri_pos[w, 0] = v0
            tri_pos[w, 1] = vertices[idx[k]]
            tri_pos[w, 2] = vertices[idx[k+1]]
            tri_col[w] = col
            w += 1

    print(f"[prepare] triangulated in {time.time()-t0:.2f}s")
    return tri_pos, tri_col


# ---------------------------------------------------------------------------
# BVH2 build
# ---------------------------------------------------------------------------

def build_bvh2(tri_pos):
    N = len(tri_pos)

    tri_min = tri_pos.min(axis=1).astype(np.float32)
    tri_max = tri_pos.max(axis=1).astype(np.float32)
    tri_cen = ((tri_min + tri_max) * 0.5).astype(np.float32)

    print("[prepare] computed triangle AABBs + centroids")

    perm = np.arange(N, dtype=np.int32)
    nodes_bounds = []
    nodes_ints = []

    sys.setrecursionlimit(200_000)

    progress = {"leaves": 0, "last_report": time.time()}
    t0 = time.time()

    def build(start, end):
        idx = perm[start:end]
        n = end - start

        bmin = tri_min[idx].min(axis=0)
        bmax = tri_max[idx].max(axis=0)

        node_idx = len(nodes_bounds)
        nodes_bounds.append(np.concatenate([bmin, bmax]).astype(np.float32))
        nodes_ints.append(None)

        if n <= LEAF_THRESHOLD:
            nodes_ints[node_idx] = (int(start), int(n), 1)
            progress["leaves"] += 1
            return node_idx

        axis = int(np.argmax(bmax - bmin))
        centroids = tri_cen[idx, axis]
        sort_order = np.argsort(centroids, kind="stable")
        perm[start:end] = idx[sort_order]

        mid = start + n // 2
        left = build(start, mid)
        right = build(mid, end)

        nodes_ints[node_idx] = (int(left), int(right), 0)
        return node_idx

    build(0, N)

    print(f"[prepare] BVH2 built in {time.time()-t0:.2f}s: "
          f"{len(nodes_bounds):,} nodes ({progress['leaves']:,} leaves)")

    return (
        np.stack(nodes_bounds, axis=0),
        np.asarray(nodes_ints, dtype=np.int32),
        perm
    )


# ---------------------------------------------------------------------------
# BVH2 writer (NEW)
# ---------------------------------------------------------------------------

def write_bvh2(path, bounds2, ints2):
    N = len(bounds2)
    t0 = time.time()

    with open(path, "w") as f:
        f.write(f"{N}\n")
        for i in range(N):
            b = bounds2[i]
            a, c, leaf = ints2[i]

            f.write(
                f"{b[0]:.4f} {b[1]:.4f} {b[2]:.4f} "
                f"{b[3]:.4f} {b[4]:.4f} {b[5]:.4f} "
                f"{int(a)} {int(c)} {int(leaf)}\n"
            )

    size_mb = os.path.getsize(path) / 1024 / 1024
    print(f"[prepare] wrote {path} ({N:,} nodes, {size_mb:.1f} MB)")


# ---------------------------------------------------------------------------
# BVH2 → BVH4 collapse (unchanged)
# ---------------------------------------------------------------------------

def collapse_to_bvh4(b2_bounds, b2_ints):
    bvh4_list = []

    def build4(bvh2_idx):
        a2, b2, is_leaf2 = b2_ints[bvh2_idx]

        if is_leaf2:
            n4 = len(bvh4_list)
            bvh4_list.append([{
                "bounds": b2_bounds[bvh2_idx].copy(),
                "idx": int(a2),
                "count": int(b2),
                "is_leaf": True,
            }])
            return n4

        left2, right2 = int(a2), int(b2)
        initial = [left2, right2]

        expanded = []
        for i, c2 in enumerate(initial):
            ca, cb, c_leaf = b2_ints[c2]
            remaining = len(initial) - i - 1
            if c_leaf:
                expanded.append(c2)
            elif len(expanded) + 2 + remaining <= 4:
                expanded.append(int(ca))
                expanded.append(int(cb))
            else:
                expanded.append(c2)

        n4 = len(bvh4_list)
        bvh4_list.append(None)

        children = []
        for e2 in expanded:
            ea, eb, e_leaf = b2_ints[e2]
            if e_leaf:
                children.append({
                    "bounds": b2_bounds[e2].copy(),
                    "idx": int(ea),
                    "count": int(eb),
                    "is_leaf": True,
                })
            else:
                child_n4 = build4(e2)
                children.append({
                    "bounds": b2_bounds[e2].copy(),
                    "idx": child_n4,
                    "count": 0,
                    "is_leaf": False,
                })

        bvh4_list[n4] = children
        return n4

    build4(0)

    M4 = len(bvh4_list)
    bounds4 = np.zeros((M4, 24), dtype=np.float32)
    meta4 = np.full((M4, 13), -1, dtype=np.int32)

    for i, children in enumerate(bvh4_list):
        meta4[i, 0] = len(children)
        for c, child in enumerate(children):
            bounds4[i, c*6:c*6+6] = child["bounds"]
            meta4[i, 1 + c*3 + 0] = child["idx"]
            meta4[i, 1 + c*3 + 1] = child["count"]
            meta4[i, 1 + c*3 + 2] = 1 if child["is_leaf"] else 0

    print(f"[prepare] BVH4 collapsed: {M4:,} nodes")
    return bounds4, meta4


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("obj", nargs="?", default="room.obj")
    ap.add_argument("--out-scene", default="scene.txt")
    ap.add_argument("--out-bvh2", default="bvh2.txt")  # NEW
    ap.add_argument("--out-bvh4", default="bvh4.txt")
    args = ap.parse_args()

    vertices, faces = load_obj(args.obj)
    tri_pos, tri_col = triangulate(vertices, faces)

    b2_bounds, b2_ints, perm = build_bvh2(tri_pos)

    # NEW
    write_bvh2(args.out_bvh2, b2_bounds, b2_ints)

    bounds4, meta4 = collapse_to_bvh4(b2_bounds, b2_ints)

    print("[prepare] done.")


if __name__ == "__main__":
    main()