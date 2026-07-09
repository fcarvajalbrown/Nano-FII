"""
manuscript/generate_figures.py
==============================
Regenerate the manuscript figures from the live benchmark in results.py.
All numbers come from compute_results(); nothing is hardcoded.

    python manuscript/generate_figures.py   # -> manuscript/figures/*.png
"""

import os
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from results import compute_results  # noqa: E402

FIG = os.path.join(HERE, "figures")
os.makedirs(FIG, exist_ok=True)

DPI = 300
LABELS = {
    "scalar_add_i64": "scalar\n(add i64)",
    "float_mul_f64": "float\n(mul f64)",
    "string_strlen": "string\n(strlen)",
    "multi_return_divmod": "multi-return\n(divmod)",
    "buffer_fill": "zero-copy\n(buffer fill)",
}


def fig_overhead(r):
    keys = list(LABELS.keys())
    vals = [r["overhead_ns"][k] for k in keys]
    fig, ax = plt.subplots(figsize=(6.4, 3.6))
    bars = ax.bar([LABELS[k] for k in keys], vals, color="#3b6ea5")
    ax.set_ylabel("Call overhead (ns)")
    ax.set_title("Nano-FFI per-call overhead by argument kind")
    ax.margins(y=0.15)
    for b, v in zip(bars, vals):
        ax.text(b.get_x() + b.get_width() / 2, v, f"{v:.0f}",
                ha="center", va="bottom", fontsize=9)
    fig.tight_layout()
    out = os.path.join(FIG, "fig_overhead.png")
    fig.savefig(out, dpi=DPI)
    plt.close(fig)
    return out


def fig_vs_ctypes(r):
    names = ["ctypes\n(baseline)", "Nano-FFI\n(add i64)"]
    vals = [r["ctypes_ns"], r["add_ns"]]
    fig, ax = plt.subplots(figsize=(4.2, 3.6))
    bars = ax.bar(names, vals, color=["#999999", "#3b6ea5"])
    ax.set_ylabel("Call overhead (ns)")
    ax.set_title(f"{r['speedup_vs_ctypes']:.1f}x lower overhead than ctypes")
    ax.margins(y=0.15)
    for b, v in zip(bars, vals):
        ax.text(b.get_x() + b.get_width() / 2, v, f"{v:.0f}",
                ha="center", va="bottom", fontsize=9)
    fig.tight_layout()
    out = os.path.join(FIG, "fig_vs_ctypes.png")
    fig.savefig(out, dpi=DPI)
    plt.close(fig)
    return out


if __name__ == "__main__":
    r = compute_results()
    for f in (fig_overhead(r), fig_vs_ctypes(r)):
        print("wrote", f)
