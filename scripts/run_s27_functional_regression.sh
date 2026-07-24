#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.."
    pwd
)"

cd "$ROOT_DIR"

CELL_MODELS="tech/osu035/osu035_stdcells.v"
PRESCAN_NETLIST="netlists/s27.nl.v"
POSTSCAN_NETLIST="netlists/s27.chained.v"
TESTBENCH="verification/s27_functional_equivalence_tb.sv"

BUILD_DIR="build/s27"
RESULT_DIR="results/s27"

RENAMED_PRESCAN="$BUILD_DIR/s27_prescan_renamed.v"
SIMULATION_BINARY="$BUILD_DIR/s27_functional_equivalence.vvp"
RESULT_LOG="$RESULT_DIR/s27_functional_equivalence.log"

for tool in python3 iverilog vvp; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[ERROR] Required tool not found: $tool" >&2
        exit 1
    fi
done

for required_file in \
    "$CELL_MODELS" \
    "$PRESCAN_NETLIST" \
    "$POSTSCAN_NETLIST" \
    "$TESTBENCH"
do
    if [[ ! -f "$required_file" ]]; then
        echo "[ERROR] Required file not found: $required_file" >&2
        exit 1
    fi
done

mkdir -p "$BUILD_DIR" "$RESULT_DIR"

echo "Preparing renamed pre-scan netlist..."

python3 - "$PRESCAN_NETLIST" "$RENAMED_PRESCAN" <<'PY'
from pathlib import Path
import re
import sys

source_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])

text = source_path.read_text(encoding="utf-8")

pattern = re.compile(
    r"(?m)^(\s*)module\s+s27\b"
)

def rename_module(match: re.Match[str]) -> str:
    indentation = match.group(1)
    return f"{indentation}module s27_prescan"

renamed_text, replacement_count = pattern.subn(
    rename_module,
    text,
    count=1,
)

if replacement_count != 1:
    raise SystemExit(
        "Expected exactly one top-level `module s27` declaration, "
        f"found {replacement_count}"
    )

output_path.write_text(
    renamed_text,
    encoding="utf-8",
)

print(f"Generated {output_path}")
PY

echo "Compiling functional regression..."

iverilog -g2012 \
    -s tb_s27_functional_equivalence \
    -o "$SIMULATION_BINARY" \
    "$CELL_MODELS" \
    "$RENAMED_PRESCAN" \
    "$POSTSCAN_NETLIST" \
    "$TESTBENCH"

echo "Running functional regression..."

set +e

vvp "$SIMULATION_BINARY" 2>&1 \
    | tee "$RESULT_LOG"

simulation_exit_code="${PIPESTATUS[0]}"

set -e

if [[ "$simulation_exit_code" -ne 0 ]]; then
    echo "[FAIL] Simulation exited with code $simulation_exit_code" >&2
    exit "$simulation_exit_code"
fi

if ! grep -qF \
    "FUNCTIONAL REGRESSION PASS: 1000 cycles" \
    "$RESULT_LOG"
then
    echo "[FAIL] Expected PASS marker was not found" >&2
    exit 1
fi

if grep -Eq \
    "FUNCTIONAL MISMATCH|FATAL|FAIL" \
    "$RESULT_LOG"
then
    echo "[FAIL] Failure marker found in simulation log" >&2
    exit 1
fi

echo
echo "[PASS] s27 functional-mode regression"
echo "Log: $RESULT_LOG"
