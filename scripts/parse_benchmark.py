#!/usr/bin/env python3
"""Parse benchmark_baseline.txt and print a Markdown benchmark table.

Usage:
    python3 scripts/parse_benchmark.py [benchmark_baseline.txt]
"""

import re
import sys


# ── Table parsing ─────────────────────────────────────────────────────────────

def _parse_table(lines, start):
    """Parse a ╒…╛ box-drawing table. Returns (metrics, end_index).

    metrics is {metric_name: p50_value} where metric_name has trailing ' *' stripped.
    end_index points at the ╘ line.
    """
    metrics = {}
    p50_col = None
    i = start
    while i < len(lines):
        stripped = lines[i].rstrip("\n").strip()
        if stripped.startswith("╘"):
            return metrics, i
        if stripped.startswith("│"):
            # split on │, drop the leading and trailing empty cells
            cells = [c.strip() for c in lines[i].split("│")[1:-1]]
            if not cells:
                i += 1
                continue
            first = cells[0]
            if first == "Metric":
                for ci, col in enumerate(cells):
                    if col == "p50":
                        p50_col = ci
                        break
            elif p50_col is not None and first:
                key = first.rstrip(" *")
                if p50_col < len(cells):
                    try:
                        metrics[key] = float(cells[p50_col])
                    except ValueError:
                        pass
        i += 1
    return metrics, i


def parse_baseline(path):
    """Return (benchmarks, success_rates).

    benchmarks: list of {'name': str, 'metrics': dict}
    success_rates: {finder_class_name: float}  e.g. {'PreindexFinder': 0.848}
    """
    with open(path, encoding="utf-8") as f:
        lines = f.readlines()

    success_rates = {}
    for line in lines:
        m = re.search(
            r"(\w+Finder)\s+benchmark stats\s*-\s*Success:\s*(\d+),\s*Errors:\s*(\d+)",
            line,
        )
        if m:
            success = int(m.group(2))
            total = success + int(m.group(3))
            if total > 0:
                success_rates[m.group(1)] = success / total

    benchmarks = []
    pending_name = None
    i = 0
    while i < len(lines):
        line = lines[i].rstrip("\n")
        stripped = line.strip()

        if stripped.startswith("╒"):
            if pending_name:
                metrics, end = _parse_table(lines, i + 1)
                benchmarks.append({"name": pending_name, "metrics": metrics})
                pending_name = None
                i = end + 1
                continue
        elif stripped and not stripped[0] in "│╞├╘╒─═":
            # Candidate benchmark name: verify the next non-empty line is a table.
            j = i + 1
            while j < len(lines) and not lines[j].strip():
                j += 1
            if j < len(lines) and lines[j].strip().startswith("╒"):
                pending_name = stripped

        i += 1

    return benchmarks, success_rates


# ── Metric extraction ─────────────────────────────────────────────────────────

def _get_wall_ms(metrics):
    for key, val in metrics.items():
        if "Time (wall clock)" not in key:
            continue
        if "(ms)" in key:
            return val
        if "(μs)" in key or "(µs)" in key:
            return val / 1_000
        if "(ns)" in key:
            return val / 1_000_000
    return None


def _get_memory_mb(metrics):
    for key, val in metrics.items():
        if "Memory (resident peak)" not in key or "Δ" in key:
            continue
        if "(M)" in key:
            return int(val)
        if "(K)" in key:
            return int(val / 1024)
    return None


def _get_instructions_str(metrics):
    for key, val in metrics.items():
        if "Instructions" not in key:
            continue
        if "(G)" in key:
            return f"{int(val)} G"
        if "(M)" in key:
            g = val / 1_000
            return f"~{g:.1f} G"
        if "(K)" in key:
            m = val / 1_000
            return f"~{m:.1f} M"
        # Raw count (no unit suffix) — typical for per-call benchmarks
        k = val / 1_000
        return f"~{k:.1f} K"
    return None


# ── Benchmark ordering ────────────────────────────────────────────────────────

# Desired display order matches the definition order in TimezoneFinderBenchmarks.swift.
# The benchmark runner executes alphabetically; this list restores the original order.
_BENCHMARK_ORDER = [
    "TZF.DefaultFinder",
    "TZF.DefaultFinder (per call)",
    "TZF.PreindexFinder",
    "TZF.PreindexFinder (per call)",
    "TZF.Finder",
    "TZF.Finder (per call)",
    "LatLongToTimezone",
    "LatLongToTimezone (per call)",
    "SwiftTimeZoneLookup.simple",
    "SwiftTimeZoneLookup.simple (per call)",
    "SwiftTimeZoneLookup.lookup",
    "SwiftTimeZoneLookup.lookup (per call)",
]


def _sort_key(benchmark):
    display = _display_name(benchmark["name"])
    for i, prefix in enumerate(_BENCHMARK_ORDER):
        if display.startswith(prefix):
            return i
    return len(_BENCHMARK_ORDER)


# ── Name helpers ──────────────────────────────────────────────────────────────

_SCALE_PATTERNS = [
    (r"\.(\d+)_million\b", 1_000_000),
    (r"\.(\d+)_thousand\b", 1_000),
    (r"\.(\d+)_hundred\b", 100),
]

_PER_CALL_PATTERN = re.compile(r"\.per_call$")

# Method names that are implementation details, not part of the display name.
_METHOD_SUFFIXES = ["getTimezone", "getTimezones", "latLngToTimezoneString"]


def _extract_scale(name):
    for pattern, multiplier in _SCALE_PATTERNS:
        m = re.search(pattern, name)
        if m:
            return int(m.group(1)) * multiplier
    return None


def _is_per_call(name):
    return bool(_PER_CALL_PATTERN.search(name))


def _display_name(name):
    # Strip the .random.N_scale suffix or .per_call suffix
    n = re.sub(r"(\.random\.\d+_\w+|\.per_call)$", "", name)
    # Strip known method suffixes
    for suffix in _METHOD_SUFFIXES:
        if n.endswith("." + suffix):
            n = n[: -len("." + suffix)]
            break
    # Strip grouping prefix used in the benchmark file
    n = re.sub(r"^OtherPackageToCompare\.", "", n)
    # Annotate per-call benchmarks so they remain distinguishable
    if _is_per_call(name):
        n += " (per call)"
    return n


# ── Table rendering ───────────────────────────────────────────────────────────

_HEADERS = [
    "Implementation",
    "Test Scale",
    "Execution Time (ms)",
    "Success Rate",
    "Operations per Second (op/sec)",
    "Time per Op",
    "Memory Usage (Peak MB)",
    "Instructions",
]


def _format_time_per_op(wall_ms, scale):
    if wall_ms is None or not scale:
        return "-"
    ns = (wall_ms / scale) * 1_000_000
    if ns < 1_000:
        return f"{ns:.0f} ns"
    us = ns / 1_000
    if us < 1_000:
        return f"{us:.1f} μs"
    return f"{us / 1_000:.1f} ms"


def _build_rows(benchmarks, success_rates):
    rows = []
    for b in benchmarks:
        name = b["name"]
        metrics = b["metrics"]
        scale = _extract_scale(name)
        per_call = _is_per_call(name)
        display = _display_name(name)
        wall_ms = _get_wall_ms(metrics)
        mem_mb = _get_memory_mb(metrics)
        instr_g = _get_instructions_str(metrics)

        mem_str = str(mem_mb) if mem_mb is not None else "-"
        instr_str = instr_g if instr_g is not None else "-"

        if per_call:
            # wall_ms is already the per-iteration (per-call) latency reported by the framework
            scale_str = "per call"
            wall_str = f"{wall_ms:.3f}" if wall_ms is not None else "-"
            ops_str = f"~{int(1000 / wall_ms):,}" if wall_ms else "-"
            time_per_op_str = _format_time_per_op(wall_ms, 1)
        else:
            scale_str = f"{scale:,}" if scale is not None else "-"
            wall_str = f"{int(wall_ms):,}" if wall_ms is not None else "-"
            ops_str = f"~{int(scale / (wall_ms / 1000)):,}" if (wall_ms and scale) else "-"
            time_per_op_str = _format_time_per_op(wall_ms, scale)

        sr = "100%"
        for finder_cls, rate in success_rates.items():
            if finder_cls in name:
                sr = f"~{rate * 100:.0f}%"
                break

        rows.append([f"`{display}`", scale_str, wall_str, sr, ops_str, time_per_op_str, mem_str, instr_str])
    return rows


def render_markdown_table(benchmarks, success_rates):
    benchmarks = sorted(benchmarks, key=_sort_key)
    rows = _build_rows(benchmarks, success_rates)
    if not rows:
        return ""

    widths = [
        max(len(_HEADERS[i]), max(len(r[i]) for r in rows))
        for i in range(len(_HEADERS))
    ]

    def fmt(cells):
        return "| " + " | ".join(c.ljust(w) for c, w in zip(cells, widths)) + " |"

    lines = [
        fmt(_HEADERS),
        "| " + " | ".join("-" * w for w in widths) + " |",
    ]
    lines += [fmt(r) for r in rows]
    return "\n".join(lines)


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "benchmark_baseline.txt"
    benchmarks, success_rates = parse_baseline(path)
    if not benchmarks:
        print("No benchmarks found.", file=sys.stderr)
        sys.exit(1)
    print(render_markdown_table(benchmarks, success_rates))


if __name__ == "__main__":
    main()
