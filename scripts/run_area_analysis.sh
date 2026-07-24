#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.."
    pwd
)"

cd "$ROOT_DIR"

LIBERTY="tech/osu035/osu035_stdcells.lib"
BUILD_DIR="build/area"

for tool in yosys python3; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[ERROR] Required tool not found: $tool" >&2
        exit 1
    fi
done

required_files=(
    "$LIBERTY"
    "scripts/generate_scan_shift_test.py"
    "scripts/summarize_area.py"
    "netlists/s27.nl.v"
    "netlists/s27.chained.v"
    "netlists/s298.nl.v"
    "netlists/s298.chain-intermediate.v"
    "netlists/s344.nl.v"
    "netlists/s344.chain-intermediate.v"
)

for required_file in "${required_files[@]}"; do
    if [[ ! -f "$required_file" ]]; then
        echo "[ERROR] Required file not found: $required_file" >&2
        exit 1
    fi
done

mkdir -p \
    "$BUILD_DIR" \
    "build/s298" \
    "build/s344" \
    "results"

run_prescan_analysis() {
    local circuit="$1"
    local log_file="$BUILD_DIR/${circuit}_prescan.log"

    echo
    echo "========================================"
    echo "Pre-scan area analysis: $circuit"
    echo "========================================"

    yosys -p "
        read_liberty -lib $LIBERTY
        read_verilog netlists/${circuit}.nl.v
        hierarchy -check -top ${circuit}
        stat -liberty $LIBERTY
    " 2>&1 | tee "$log_file"
}

run_s27_postscan_analysis() {
    local log_file="$BUILD_DIR/s27_postscan.log"

    echo
    echo "========================================"
    echo "Post-scan area analysis: s27"
    echo "========================================"

    yosys -p "
        read_liberty -lib $LIBERTY
        read_verilog netlists/s27.chained.v
        hierarchy -check -top s27
        stat -liberty $LIBERTY
    " 2>&1 | tee "$log_file"
}

run_intermediate_postscan_analysis() {
    local circuit="$1"

    local patch_dir="build/$circuit"
    local patched_netlist="$patch_dir/${circuit}_postscan_patched.v"
    local mapped_netlist="$BUILD_DIR/${circuit}_postscan_mapped.v"
    local yosys_script="$BUILD_DIR/${circuit}_postscan.ys"
    local log_file="$BUILD_DIR/${circuit}_postscan.log"

    echo
    echo "========================================"
    echo "Preparing post-scan wrapper: $circuit"
    echo "========================================"

    python3 scripts/generate_scan_shift_test.py \
        --circuit "$circuit" \
        --netlist "netlists/${circuit}.chain-intermediate.v" \
        --outdir "$patch_dir"

    if [[ ! -s "$patched_netlist" ]]; then
        echo "[ERROR] Patched netlist was not generated: $patched_netlist" >&2
        exit 1
    fi

    printf '%s\n' \
        "read_liberty -lib $LIBERTY" \
        "read_verilog $patched_netlist" \
        "hierarchy -check -top $circuit" \
        "proc" \
        "flatten" \
        "opt" \
        "techmap" \
        "opt" \
        "dfflibmap -liberty $LIBERTY" \
        "abc -liberty $LIBERTY" \
        "clean" \
        "stat -liberty $LIBERTY" \
        "write_verilog -noattr $mapped_netlist" \
        > "$yosys_script"

    echo
    echo "========================================"
    echo "Post-scan area analysis: $circuit"
    echo "========================================"

    yosys -s "$yosys_script" 2>&1 \
        | tee "$log_file"

    if [[ ! -s "$mapped_netlist" ]]; then
        echo "[ERROR] Mapped netlist was not generated: $mapped_netlist" >&2
        exit 1
    fi

    if grep -Eq \
        '\\\$_[A-Za-z0-9_]+|\\\$[A-Za-z0-9_]+' \
        "$mapped_netlist"
    then
        echo "[ERROR] Generic Yosys cells remain in $mapped_netlist" >&2
        exit 1
    fi

    echo "[PASS] $circuit post-scan netlist is fully mapped"
}

for circuit in s27 s298 s344; do
    run_prescan_analysis "$circuit"
done

run_s27_postscan_analysis
run_intermediate_postscan_analysis s298
run_intermediate_postscan_analysis s344

echo
echo "========================================"
echo "Generating area summaries"
echo "========================================"

python3 scripts/summarize_area.py

echo
echo "[PASS] Area analysis completed"
echo "CSV      : results/area_summary.csv"
echo "Markdown : results/area_summary.md"
