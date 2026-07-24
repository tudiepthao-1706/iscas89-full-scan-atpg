#!/usr/bin/env python3

from __future__ import annotations

import csv
import re
import sys
from dataclasses import dataclass
from pathlib import Path


CIRCUITS = ("s27", "s298", "s344")
LOG_DIR = Path("build/area")
CSV_OUTPUT = Path("results/area_summary.csv")
MARKDOWN_OUTPUT = Path("results/area_summary.md")

CELL_PATTERN = re.compile(
    r"Number of cells:\s+(\d+)"
)

AREA_PATTERN = re.compile(
    r"Chip area for module .*?:\s+([0-9.]+)"
)


@dataclass(frozen=True)
class AreaResult:
    circuit: str
    prescan_cells: int
    postscan_cells: int
    cell_increase: int
    cell_overhead_percent: float
    prescan_area: float
    postscan_area: float
    area_increase: float
    area_overhead_percent: float


def parse_yosys_log(path: Path) -> tuple[int, float]:
    if not path.exists():
        raise FileNotFoundError(
            f"Missing Yosys log: {path}"
        )

    text = path.read_text(
        encoding="utf-8",
        errors="replace",
    )

    cell_matches = CELL_PATTERN.findall(text)
    area_matches = AREA_PATTERN.findall(text)

    if not cell_matches:
        raise RuntimeError(
            f"Could not find cell count in {path}"
        )

    if not area_matches:
        raise RuntimeError(
            f"Could not find chip area in {path}"
        )

    cells = int(cell_matches[-1])
    area = float(area_matches[-1])

    return cells, area


def calculate_result(circuit: str) -> AreaResult:
    prescan_log = LOG_DIR / f"{circuit}_prescan.log"
    postscan_log = LOG_DIR / f"{circuit}_postscan.log"

    prescan_cells, prescan_area = parse_yosys_log(
        prescan_log
    )

    postscan_cells, postscan_area = parse_yosys_log(
        postscan_log
    )

    if prescan_cells <= 0:
        raise RuntimeError(
            f"{circuit}: invalid pre-scan cell count"
        )

    if prescan_area <= 0:
        raise RuntimeError(
            f"{circuit}: invalid pre-scan area"
        )

    cell_increase = postscan_cells - prescan_cells
    area_increase = postscan_area - prescan_area

    cell_overhead = (
        100.0 * cell_increase / prescan_cells
    )

    area_overhead = (
        100.0 * area_increase / prescan_area
    )

    return AreaResult(
        circuit=circuit,
        prescan_cells=prescan_cells,
        postscan_cells=postscan_cells,
        cell_increase=cell_increase,
        cell_overhead_percent=cell_overhead,
        prescan_area=prescan_area,
        postscan_area=postscan_area,
        area_increase=area_increase,
        area_overhead_percent=area_overhead,
    )


def write_csv(results: list[AreaResult]) -> None:
    CSV_OUTPUT.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    with CSV_OUTPUT.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as csv_file:
        writer = csv.writer(csv_file)

        writer.writerow(
            [
                "circuit",
                "prescan_cells",
                "postscan_cells",
                "cell_increase",
                "cell_overhead_percent",
                "prescan_area",
                "postscan_area",
                "area_increase",
                "area_overhead_percent",
            ]
        )

        for result in results:
            writer.writerow(
                [
                    result.circuit,
                    result.prescan_cells,
                    result.postscan_cells,
                    result.cell_increase,
                    f"{result.cell_overhead_percent:.2f}",
                    f"{result.prescan_area:.2f}",
                    f"{result.postscan_area:.2f}",
                    f"{result.area_increase:.2f}",
                    f"{result.area_overhead_percent:.2f}",
                ]
            )


def write_markdown(
    results: list[AreaResult],
) -> None:
    lines = [
        "# Pre-scan versus Post-scan Area Summary",
        "",
        (
            "| Circuit | Pre-scan cells | Post-scan cells "
            "| Cell overhead | Pre-scan area | Post-scan area "
            "| Area overhead |"
        ),
        "|---|---:|---:|---:|---:|---:|---:|",
    ]

    for result in results:
        lines.append(
            f"| `{result.circuit}` "
            f"| {result.prescan_cells} "
            f"| {result.postscan_cells} "
            f"| {result.cell_overhead_percent:.2f}% "
            f"| {result.prescan_area:.2f} "
            f"| {result.postscan_area:.2f} "
            f"| {result.area_overhead_percent:.2f}% |"
        )

    lines.extend(
        [
            "",
            "## Method",
            "",
            (
                "Pre-scan and post-scan netlists were analyzed "
                "using Yosys `stat -liberty` with the same "
                "OSU035 Liberty library."
            ),
            "",
            (
                "The `s298` and `s344` post-scan intermediate "
                "wrappers were patched in the build directory "
                "and fully technology-mapped before measurement."
            ),
            "",
            (
                "Area values are sums of standard-cell areas "
                "from the Liberty file. They are mapped "
                "cell-area estimates, not post-placement-and-"
                "routing silicon area."
            ),
            "",
            "The percentage overhead is calculated as:",
            "",
            "```text",
            (
                "(post-scan value - pre-scan value) "
                "/ pre-scan value * 100"
            ),
            "```",
            "",
            (
                "The large relative overheads are partly caused "
                "by the small benchmark sizes and by the "
                "inclusion of input and output boundary "
                "registers in the generated scan structures."
            ),
            "",
        ]
    )

    MARKDOWN_OUTPUT.write_text(
        "\n".join(lines),
        encoding="utf-8",
    )


def print_results(
    results: list[AreaResult],
) -> None:
    header = (
        f"{'Circuit':<8}"
        f"{'Pre cells':>11}"
        f"{'Post cells':>12}"
        f"{'Cell OH':>11}"
        f"{'Pre area':>12}"
        f"{'Post area':>12}"
        f"{'Area OH':>11}"
    )

    print(header)
    print("-" * len(header))

    for result in results:
        print(
            f"{result.circuit:<8}"
            f"{result.prescan_cells:>11}"
            f"{result.postscan_cells:>12}"
            f"{result.cell_overhead_percent:>10.2f}%"
            f"{result.prescan_area:>12.2f}"
            f"{result.postscan_area:>12.2f}"
            f"{result.area_overhead_percent:>10.2f}%"
        )


def main() -> int:
    try:
        results = [
            calculate_result(circuit)
            for circuit in CIRCUITS
        ]

        write_csv(results)
        write_markdown(results)
        print_results(results)

        print()
        print(f"CSV      : {CSV_OUTPUT}")
        print(f"Markdown : {MARKDOWN_OUTPUT}")

    except (
        FileNotFoundError,
        RuntimeError,
        OSError,
    ) as error:
        print(
            f"[ERROR] {error}",
            file=sys.stderr,
        )
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
