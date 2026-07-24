#!/usr/bin/env python3

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path


FAULT_SITE_PATTERN = re.compile(
    r"Found\s+(\d+)\s+fault sites",
    flags=re.IGNORECASE,
)

REPORTED_COVERAGE_PATTERN = re.compile(
    r"Simulations concluded:\s*Coverage\s+([0-9.]+)%",
    flags=re.IGNORECASE,
)


@dataclass(frozen=True)
class AtpgSummary:
    circuit: str
    fault_sites: int
    total_stuck_at_faults: int
    detected_faults: int
    undetected_faults: int
    coverage_percent: float
    tool_reported_coverage_percent: float
    compacted_patterns: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Generate an ATPG summary from Fault logs and "
            "canonical compacted ATPG reports."
        )
    )

    parser.add_argument(
        "--circuits",
        nargs="+",
        default=["s27", "s298", "s344"],
    )

    parser.add_argument(
        "--log-root",
        type=Path,
        default=Path("build/logs"),
    )

    parser.add_argument(
        "--results-root",
        type=Path,
        default=Path("results"),
    )

    parser.add_argument(
        "--csv-output",
        type=Path,
        default=Path("results/atpg_summary.csv"),
    )

    parser.add_argument(
        "--markdown-output",
        type=Path,
        default=Path("results/atpg_summary.md"),
    )

    return parser.parse_args()


def parse_fault_log(log_path: Path) -> tuple[int, float]:
    if not log_path.exists():
        raise FileNotFoundError(
            f"ATPG log not found: {log_path}"
        )

    text = log_path.read_text(
        encoding="utf-8",
        errors="replace",
    )

    site_matches = FAULT_SITE_PATTERN.findall(text)

    if not site_matches:
        raise RuntimeError(
            f"Could not find fault-site count in {log_path}"
        )

    coverage_matches = REPORTED_COVERAGE_PATTERN.findall(text)

    if not coverage_matches:
        raise RuntimeError(
            f"Could not find reported coverage in {log_path}"
        )

    fault_sites = int(site_matches[-1])
    reported_coverage = float(coverage_matches[-1])

    return fault_sites, reported_coverage


def parse_compacted_report(
    report_path: Path,
) -> tuple[int, int]:
    if not report_path.exists():
        raise FileNotFoundError(
            f"ATPG report not found: {report_path}"
        )

    report = json.loads(
        report_path.read_text(encoding="utf-8")
    )

    coverage_list = report.get("coverageList")

    if not isinstance(coverage_list, list):
        raise RuntimeError(
            f"`coverageList` is missing or invalid in {report_path}"
        )

    detected_faults: set[tuple[str, str]] = set()

    for pattern_index, entry in enumerate(coverage_list):
        if not isinstance(entry, dict):
            raise RuntimeError(
                f"Invalid pattern entry {pattern_index} "
                f"in {report_path}"
            )

        coverage = entry.get("coverage", {})

        if not isinstance(coverage, dict):
            raise RuntimeError(
                f"Invalid coverage data at pattern "
                f"{pattern_index} in {report_path}"
            )

        for polarity in ("sa0", "sa1"):
            sites = coverage.get(polarity, [])

            if not isinstance(sites, list):
                raise RuntimeError(
                    f"Invalid {polarity} list at pattern "
                    f"{pattern_index} in {report_path}"
                )

            for site in sites:
                if not isinstance(site, str):
                    raise RuntimeError(
                        f"Invalid fault-site name in {report_path}"
                    )

                detected_faults.add((site, polarity))

    return len(detected_faults), len(coverage_list)


def summarize_circuit(
    circuit: str,
    log_root: Path,
    results_root: Path,
) -> AtpgSummary:
    log_path = log_root / circuit / "atpg.log"

    report_path = (
        results_root
        / circuit
        / f"{circuit}_atpg_report.json"
    )

    fault_sites, reported_coverage = parse_fault_log(
        log_path
    )

    detected_faults, compacted_patterns = (
        parse_compacted_report(report_path)
    )

    total_faults = 2 * fault_sites
    undetected_faults = total_faults - detected_faults

    if undetected_faults < 0:
        raise RuntimeError(
            f"{circuit}: detected fault count "
            f"{detected_faults} exceeds total {total_faults}"
        )

    calculated_coverage = (
        100.0 * detected_faults / total_faults
        if total_faults
        else 0.0
    )

    coverage_difference = abs(
        calculated_coverage - reported_coverage
    )

    if coverage_difference > 0.02:
        raise RuntimeError(
            f"{circuit}: calculated coverage "
            f"{calculated_coverage:.5f}% does not match "
            f"tool-reported coverage "
            f"{reported_coverage:.5f}%"
        )

    return AtpgSummary(
        circuit=circuit,
        fault_sites=fault_sites,
        total_stuck_at_faults=total_faults,
        detected_faults=detected_faults,
        undetected_faults=undetected_faults,
        coverage_percent=calculated_coverage,
        tool_reported_coverage_percent=reported_coverage,
        compacted_patterns=compacted_patterns,
    )


def write_csv(
    summaries: list[AtpgSummary],
    output_path: Path,
) -> None:
    output_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    fieldnames = [
        "circuit",
        "fault_sites",
        "total_stuck_at_faults",
        "detected_faults",
        "undetected_faults",
        "coverage_percent",
        "tool_reported_coverage_percent",
        "compacted_patterns",
    ]

    with output_path.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as csv_file:
        writer = csv.DictWriter(
            csv_file,
            fieldnames=fieldnames,
        )

        writer.writeheader()

        for summary in summaries:
            row = asdict(summary)
            row["coverage_percent"] = (
                f"{summary.coverage_percent:.5f}"
            )
            row["tool_reported_coverage_percent"] = (
                f"{summary.tool_reported_coverage_percent:.5f}"
            )
            writer.writerow(row)


def write_markdown(
    summaries: list[AtpgSummary],
    output_path: Path,
) -> None:
    output_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    lines = [
        "# ATPG Summary",
        "",
        (
            "Generated from the canonical compacted ATPG reports "
            "under `results/<circuit>/` and the ATPG execution "
            "logs under `build/logs/<circuit>/atpg.log`."
        ),
        "",
        (
            "Each enumerated fault site contributes two single "
            "stuck-at faults: stuck-at-0 and stuck-at-1."
        ),
        "",
        (
            "| Circuit | Fault sites | Total SA faults | "
            "Detected | Undetected | Coverage | "
            "Compacted patterns |"
        ),
        (
            "|---|---:|---:|---:|---:|---:|---:|"
        ),
    ]

    for summary in summaries:
        lines.append(
            f"| `{summary.circuit}` "
            f"| {summary.fault_sites} "
            f"| {summary.total_stuck_at_faults} "
            f"| {summary.detected_faults} "
            f"| {summary.undetected_faults} "
            f"| {summary.coverage_percent:.2f}% "
            f"| {summary.compacted_patterns} |"
        )

    lines.extend(
        [
            "",
            "## Interpretation",
            "",
            (
                "- Coverage is calculated as detected single "
                "stuck-at faults divided by total enumerated "
                "single stuck-at faults."
            ),
            (
                "- Detected faults are deduplicated across all "
                "compacted test patterns."
            ),
            (
                "- Undetected does not automatically mean "
                "untestable or redundant."
            ),
            (
                "- The compacted pattern count is read from the "
                "canonical committed ATPG report."
            ),
            (
                "- PRNG-based ATPG may produce different pattern "
                "sets or compaction results across separate runs."
            ),
            "",
        ]
    )

    output_path.write_text(
        "\n".join(lines),
        encoding="utf-8",
    )


def print_summary(
    summaries: list[AtpgSummary],
) -> None:
    header = (
        f"{'Circuit':<8}"
        f"{'Sites':>8}"
        f"{'Total':>9}"
        f"{'Detected':>11}"
        f"{'Missed':>9}"
        f"{'Coverage':>12}"
        f"{'Patterns':>10}"
    )

    print(header)
    print("-" * len(header))

    for summary in summaries:
        print(
            f"{summary.circuit:<8}"
            f"{summary.fault_sites:>8}"
            f"{summary.total_stuck_at_faults:>9}"
            f"{summary.detected_faults:>11}"
            f"{summary.undetected_faults:>9}"
            f"{summary.coverage_percent:>11.2f}%"
            f"{summary.compacted_patterns:>10}"
        )


def main() -> int:
    args = parse_args()

    try:
        summaries = [
            summarize_circuit(
                circuit=circuit,
                log_root=args.log_root,
                results_root=args.results_root,
            )
            for circuit in args.circuits
        ]

        write_csv(
            summaries,
            args.csv_output,
        )

        write_markdown(
            summaries,
            args.markdown_output,
        )

        print_summary(summaries)

        print()
        print(f"CSV      : {args.csv_output}")
        print(f"Markdown : {args.markdown_output}")

    except (
        FileNotFoundError,
        json.JSONDecodeError,
        RuntimeError,
    ) as error:
        print(
            f"[ERROR] {error}",
            file=sys.stderr,
        )
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
