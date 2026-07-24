#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.."
    pwd
)"

cd "$ROOT_DIR"

BUILD_DIR="build/regression"
RESULT_DIR="results"

CELL_MODELS="tech/osu035/osu035_stdcells.v"

mkdir -p \
    "$BUILD_DIR" \
    "build/s27" \
    "build/s298" \
    "build/s344" \
    "results/s27" \
    "results/s298" \
    "results/s344"

required_tools=(
    python3
    iverilog
    vvp
    yosys
)

for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[ERROR] Required tool not found: $tool" >&2
        exit 1
    fi
done

required_files=(
    "$CELL_MODELS"
    "netlists/s27.chained.v"
    "netlists/s27.nl.v"
    "netlists/s298.chain-intermediate.v"
    "netlists/s344.chain-intermediate.v"
    "verification/s27_golden_comb.sv"
    "verification/s27_scan_capture_tb.sv"
    "verification/s27_functional_equivalence_tb.sv"
    "scripts/generate_scan_shift_test.py"
    "scripts/run_s27_functional_regression.sh"
    "scripts/run_area_analysis.sh"
    "scripts/summarize_area.py"
)

for required_file in "${required_files[@]}"; do
    if [[ ! -f "$required_file" ]]; then
        echo "[ERROR] Required file not found: $required_file" >&2
        exit 1
    fi
done

run_logged() {
    local name="$1"
    shift

    local log_file="$BUILD_DIR/${name}.log"

    echo
    echo "=================================================="
    echo "Running: $name"
    echo "=================================================="

    set +e

    "$@" 2>&1 | tee "$log_file"

    local command_exit_code="${PIPESTATUS[0]}"

    set -e

    if [[ "$command_exit_code" -ne 0 ]]; then
        echo "[FAIL] $name exited with code $command_exit_code" >&2
        echo "[FAIL] Log: $log_file" >&2
        exit "$command_exit_code"
    fi

    echo "[PASS] $name"
}

require_marker() {
    local log_file="$1"
    local marker="$2"

    if ! grep -qF "$marker" "$log_file"; then
        echo "[FAIL] Expected marker not found in $log_file" >&2
        echo "[FAIL] Missing marker: $marker" >&2
        exit 1
    fi
}

reject_failure_markers() {
    local log_file="$1"

    if grep -Eq \
        'FATAL|MISMATCH|SHIFT-CAPTURE-SHIFT FAIL|SCAN SHIFT FAIL' \
        "$log_file"
    then
        echo "[FAIL] Failure marker found in $log_file" >&2
        exit 1
    fi
}

echo
echo "=================================================="
echo "DFT regression suite"
echo "=================================================="

# --------------------------------------------------
# s27 true shift-capture-shift verification
# --------------------------------------------------

run_logged \
    "s27_scan_capture_compile" \
    iverilog -g2012 \
        -s tb_s27_scan_capture \
        -o build/s27/s27_scan_capture.vvp \
        "$CELL_MODELS" \
        netlists/s27.chained.v \
        verification/s27_golden_comb.sv \
        verification/s27_scan_capture_tb.sv

run_logged \
    "s27_scan_capture_simulation" \
    vvp build/s27/s27_scan_capture.vvp

cp \
    "$BUILD_DIR/s27_scan_capture_simulation.log" \
    results/s27/s27_scan_capture.log

require_marker \
    results/s27/s27_scan_capture.log \
    "SHIFT-CAPTURE-SHIFT PASS"

reject_failure_markers \
    results/s27/s27_scan_capture.log

# --------------------------------------------------
# s298 serial scan-integrity verification
# --------------------------------------------------

run_logged \
    "s298_test_generation" \
    python3 scripts/generate_scan_shift_test.py \
        --circuit s298 \
        --netlist netlists/s298.chain-intermediate.v \
        --outdir build/s298

run_logged \
    "s298_scan_compile" \
    iverilog -g2012 \
        -s tb_s298_scan_shift \
        -o build/s298/s298_scan_shift.vvp \
        "$CELL_MODELS" \
        build/s298/s298_postscan_patched.v \
        build/s298/s298_scan_shift_tb.sv

run_logged \
    "s298_scan_simulation" \
    vvp build/s298/s298_scan_shift.vvp

cp \
    "$BUILD_DIR/s298_scan_simulation.log" \
    results/s298/s298_scan_shift.log

require_marker \
    results/s298/s298_scan_shift.log \
    "SCAN SHIFT PASS"

reject_failure_markers \
    results/s298/s298_scan_shift.log

# --------------------------------------------------
# s344 serial scan-integrity verification
# --------------------------------------------------

run_logged \
    "s344_test_generation" \
    python3 scripts/generate_scan_shift_test.py \
        --circuit s344 \
        --netlist netlists/s344.chain-intermediate.v \
        --outdir build/s344

run_logged \
    "s344_scan_compile" \
    iverilog -g2012 \
        -s tb_s344_scan_shift \
        -o build/s344/s344_scan_shift.vvp \
        "$CELL_MODELS" \
        build/s344/s344_postscan_patched.v \
        build/s344/s344_scan_shift_tb.sv

run_logged \
    "s344_scan_simulation" \
    vvp build/s344/s344_scan_shift.vvp

cp \
    "$BUILD_DIR/s344_scan_simulation.log" \
    results/s344/s344_scan_shift.log

require_marker \
    results/s344/s344_scan_shift.log \
    "SCAN SHIFT PASS"

reject_failure_markers \
    results/s344/s344_scan_shift.log

# --------------------------------------------------
# s27 functional-mode regression
# --------------------------------------------------

run_logged \
    "s27_functional_regression" \
    bash scripts/run_s27_functional_regression.sh

require_marker \
    results/s27/s27_functional_equivalence.log \
    "FUNCTIONAL REGRESSION PASS: 1000 cycles"

reject_failure_markers \
    results/s27/s27_functional_equivalence.log

# --------------------------------------------------
# ATPG summary
# --------------------------------------------------

atpg_logs_available=yes

for circuit in s27 s298 s344; do
    if [[ ! -f "build/logs/$circuit/atpg.log" ]]; then
        atpg_logs_available=no
    fi
done

if [[ "$atpg_logs_available" == "yes" ]]; then
    if [[ ! -f scripts/summarize_atpg.py ]]; then
        echo "[ERROR] Missing scripts/summarize_atpg.py" >&2
        exit 1
    fi

    run_logged \
        "atpg_summary" \
        python3 scripts/summarize_atpg.py
else
    echo
    echo "=================================================="
    echo "ATPG summary"
    echo "=================================================="
    echo "[SKIP] ATPG execution logs are not available."
    echo "       Run scripts/run_pipeline.sh first to regenerate them."
fi

# --------------------------------------------------
# Area analysis
# --------------------------------------------------

run_logged \
    "area_analysis" \
    bash scripts/run_area_analysis.sh

# --------------------------------------------------
# Final summary
# --------------------------------------------------

echo
echo "=================================================="
echo "Regression summary"
echo "=================================================="
echo "[PASS] s27 shift-capture-shift"
echo "[PASS] s298 serial scan integrity"
echo "[PASS] s344 serial scan integrity"
echo "[PASS] s27 functional-mode regression"
echo "[PASS] pre-scan versus post-scan area analysis"

if [[ "$atpg_logs_available" == "yes" ]]; then
    echo "[PASS] ATPG coverage summary"
else
    echo "[SKIP] ATPG coverage summary: execution logs unavailable"
fi

echo
echo "All required regressions passed."
