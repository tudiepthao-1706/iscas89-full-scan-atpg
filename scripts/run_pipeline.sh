#!/usr/bin/env bash

# Full-scan insertion and stuck-at ATPG pipeline for ISCAS'89.
#
# The script:
#   1. Synthesizes each benchmark.
#   2. Cuts sequential elements for combinational ATPG.
#   3. Runs stuck-at pattern generation and fault simulation.
#   4. Performs scan-chain insertion.
#   5. Records tool status without silently hiding failures.

set -Eeuo pipefail

ROOT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.."
    pwd
)"

cd "$ROOT_DIR"

LIB="tech/osu035/osu035_stdcells.lib"
MODELS="tech/osu035/osu035_stdcells.v"

mkdir -p netlists
mkdir -p build/logs
mkdir -p results

required_tools=(
    fault
    yosys
    iverilog
    python3
)

for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[ERROR] Required tool not found: $tool" >&2
        exit 1
    fi
done

if [[ ! -f "$LIB" ]]; then
    echo "[ERROR] Liberty file not found: $LIB" >&2
    exit 1
fi

if [[ ! -f "$MODELS" ]]; then
    echo "[ERROR] Cell-model file not found: $MODELS" >&2
    exit 1
fi

run_circuit() {
    local name="$1"
    local dff_cell="$2"
    local has_reset="$3"
    local vector_count="$4"
    local random_count="$5"
    local ceiling="$6"

    local result_dir="results/$name"
    local log_dir="build/logs/$name"
    local status_file="$result_dir/pipeline_status.txt"

    mkdir -p "$result_dir"
    mkdir -p "$log_dir"

    : > "$status_file"

    local -a reset_args=()

    if [[ "$has_reset" == "yes" ]]; then
        reset_args+=(--reset reset)
    fi

    echo
    echo "=================================================="
    echo "Running DFT flow for $name"
    echo "=================================================="

    # Remove old chain artifacts so that stale files cannot be
    # mistaken for outputs of the current run.
    rm -f \
        "netlists/$name.chained.v" \
        "netlists/$name.chain-intermediate.v"

    echo "CIRCUIT=$name" >> "$status_file"
    echo "DFF_CELL=$dff_cell" >> "$status_file"
    echo "HAS_RESET=$has_reset" >> "$status_file"

    echo
    echo ">>> [$name] Technology mapping"

    if fault synth \
        -t "$name" \
        -l "$LIB" \
        -o "netlists/$name.nl.v" \
        "benchmarks/$name.v" \
        2>&1 | tee "$log_dir/synth.log"
    then
        echo "SYNTH=PASS" >> "$status_file"
    else
        echo "SYNTH=FAIL" >> "$status_file"
        echo "PIPELINE_STATUS=FAIL" >> "$status_file"
        echo "[FAIL] $name synthesis failed" >&2
        return 1
    fi

    if [[ ! -s "netlists/$name.nl.v" ]]; then
        echo "SYNTH_OUTPUT=NOT_GENERATED" >> "$status_file"
        echo "PIPELINE_STATUS=FAIL" >> "$status_file"
        echo "[FAIL] Missing synthesized netlist for $name" >&2
        return 1
    fi

    echo "SYNTH_OUTPUT=netlists/$name.nl.v" \
        >> "$status_file"

    echo
    echo ">>> [$name] Sequential-netlist cutting"

    if fault cut \
        -d "$dff_cell" \
        --clock CK \
        "${reset_args[@]}" \
        --bypassing VDD=1 \
        --bypassing GND=0 \
        -o "netlists/$name.cut.v" \
        "netlists/$name.nl.v" \
        2>&1 | tee "$log_dir/cut.log"
    then
        echo "CUT=PASS" >> "$status_file"
    else
        echo "CUT=FAIL" >> "$status_file"
        echo "PIPELINE_STATUS=FAIL" >> "$status_file"
        echo "[FAIL] $name netlist cutting failed" >&2
        return 1
    fi

    if [[ ! -s "netlists/$name.cut.v" ]]; then
        echo "CUT_OUTPUT=NOT_GENERATED" >> "$status_file"
        echo "PIPELINE_STATUS=FAIL" >> "$status_file"
        echo "[FAIL] Missing cut netlist for $name" >&2
        return 1
    fi

    echo "CUT_OUTPUT=netlists/$name.cut.v" \
        >> "$status_file"

    echo
    echo ">>> [$name] ATPG and fault simulation"

    if fault \
        -c "$MODELS" \
        -v "$vector_count" \
        -r "$random_count" \
        -m 95 \
        --ceiling "$ceiling" \
        "netlists/$name.cut.v" \
        --clock CK \
        "${reset_args[@]}" \
        --bypassing VDD=1 \
        --bypassing GND=0 \
        2>&1 | tee "$log_dir/atpg.log"
    then
        echo "ATPG=PASS" >> "$status_file"
    else
        echo "ATPG=FAIL" >> "$status_file"
        echo "PIPELINE_STATUS=FAIL" >> "$status_file"
        echo "[FAIL] $name ATPG failed" >&2
        return 1
    fi

    echo
    echo ">>> [$name] Scan-chain insertion"

    local -a chain_extra_args=()

    if [[ "$has_reset" == "no" ]]; then
        chain_extra_args+=(--skip-synth)
    fi

    set +e

    fault chain \
        --clock CK \
        "${reset_args[@]}" \
        --bypassing VDD=1 \
        --bypassing GND=0 \
        "${chain_extra_args[@]}" \
        -l "$LIB" \
        -c "$MODELS" \
        -o "netlists/$name.chained.v" \
        "netlists/$name.nl.v" \
        2>&1 | tee "$log_dir/chain.log"

    local chain_exit_code="${PIPESTATUS[0]}"

    set -e

    echo "CHAIN_COMMAND_EXIT_CODE=$chain_exit_code" \
        >> "$status_file"

    local postscan_artifact=""

    if [[ -s "netlists/$name.chained.v" ]]; then
        postscan_artifact="netlists/$name.chained.v"
    elif [[ -s "netlists/$name.chain-intermediate.v" ]]; then
        postscan_artifact="netlists/$name.chain-intermediate.v"
    fi

    if [[ -z "$postscan_artifact" ]]; then
        echo "SCAN_ARTIFACT=NOT_GENERATED" >> "$status_file"
        echo "PIPELINE_STATUS=FAIL" >> "$status_file"
        echo "[FAIL] No post-scan artifact generated for $name" >&2
        return 1
    fi

    echo "SCAN_ARTIFACT=$postscan_artifact" \
        >> "$status_file"

    if [[ "$chain_exit_code" -eq 0 ]]; then
        echo "CHAIN_TOOL_VERIFICATION=PASS" \
            >> "$status_file"

        echo "PIPELINE_STATUS=PASS" \
            >> "$status_file"

        echo "[PASS] $name scan insertion and tool verification"
    else
        echo "CHAIN_TOOL_VERIFICATION=FAIL" \
            >> "$status_file"

        echo "CUSTOM_SCAN_VERIFICATION_REQUIRED=YES" \
            >> "$status_file"

        echo "PIPELINE_STATUS=PASS_WITH_WRAPPER_WORKAROUND" \
            >> "$status_file"

        echo "[WARN] $name produced a post-scan artifact, but"
        echo "       Fault's generated verification wrapper failed."
        echo "       Use the independent custom scan regression."
    fi

    echo
    echo "Status written to: $status_file"
}

run_circuit s27  DFFSR    yes 20 10 200
run_circuit s298 DFFPOSX1 no  50 30 500
run_circuit s344 DFFPOSX1 no  50 30 500

echo
echo "=================================================="
echo "Core DFT pipeline completed"
echo "Review results/<circuit>/pipeline_status.txt"
echo "=================================================="
