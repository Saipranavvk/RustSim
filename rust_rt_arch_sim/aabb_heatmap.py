import os
import numpy as np
import matplotlib.pyplot as plt

# ============================================================
# CONFIG
# ============================================================

INPUT_NPY = "./src/sim_logs/aabb_intersect_section_avg_cycles.npy"
OUTPUT_PNG = "aabb_intersect_core_heatmap.png"

# ============================================================
# LOAD
# ============================================================

#
# Expected shape:
#
# [cores_y, cores_x, contexts]
#
# Example:
#   [64, 128, 16]
#

data = np.load(INPUT_NPY)

if data.ndim != 3:
    raise RuntimeError(
        f"Expected 3D tensor [Y, X, CTX], got shape {data.shape}"
    )

cores_y, cores_x, ctx_cnt = data.shape

print("Loaded tensor:", data.shape)

# ============================================================
# AVERAGE OVER CONTEXTS
# ============================================================

#
# Ignore contexts with zero samples.
# Otherwise idle contexts drag averages down badly.
#

valid_mask = data > 0

valid_count = np.sum(valid_mask, axis=2)

core_avg = np.divide(
    np.sum(data, axis=2),
    valid_count,
    out=np.zeros((cores_y, cores_x), dtype=np.float32),
    where=valid_count > 0
)

# ============================================================
# NORMALIZATION
# ============================================================

nonzero = core_avg[core_avg > 0]

if len(nonzero) == 0:
    vmax = 1.0
else:
    #
    # Prevent a few pathological cores
    # from destroying contrast.
    #
    vmax = np.percentile(nonzero, 99)

print("vmax =", vmax)

# ============================================================
# PLOT
# ============================================================

plt.figure(figsize=(24, 12))

im = plt.imshow(
    core_avg,
    cmap="inferno",
    interpolation="nearest",
    origin="upper",
    vmin=0,
    vmax=vmax
)

plt.colorbar(
    im,
    label="Average Active Cycles in AABB_INTERSECT"
)

plt.title(
    "Average Active Cycles Spent in AABB_INTERSECT Per Core"
)

plt.xlabel("Core X")
plt.ylabel("Core Y")

# ============================================================
# OPTIONAL VALUE LABELS
# ============================================================

#
# Only do this for reasonably small meshes.
#

if cores_x <= 32 and cores_y <= 32:
    for y in range(cores_y):
        for x in range(cores_x):

            val = core_avg[y, x]

            plt.text(
                x,
                y,
                f"{val:.1f}",
                ha="center",
                va="center",
                fontsize=6,
                color="white" if val < vmax * 0.5 else "black"
            )

plt.tight_layout()

plt.savefig(OUTPUT_PNG, dpi=300)

print("Saved:", OUTPUT_PNG)