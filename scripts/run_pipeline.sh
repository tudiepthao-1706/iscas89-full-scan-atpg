#!/usr/bin/env bash
# Full-Scan Insertion + Stuck-at ATPG pipeline on ISCAS'89 benchmarks
# Tools: Yosys (via fault synth), Fault (AUCOHL/Fault, fault-dft on PyPI), Icarus Verilog
# Requires: pip install fault-dft ; apt install iverilog
set -e

LIB=tech/osu035/osu035_stdcells.lib
MODELS=tech/osu035/osu035_stdcells.v
mkdir -p netlists

run_circuit () {
  local NAME=$1
  local DFF=$2
  local HAS_RESET=$3   # "yes" or "no"
  local V=$4 R=$5 CEIL=$6

  echo ">>> [$NAME] synth"
  fault synth -t "$NAME" -l "$LIB" -o "netlists/$NAME.nl.v" "benchmarks/$NAME.v"

  if [ "$HAS_RESET" = "yes" ]; then
    RESET_ARGS="--reset reset"
  else
    RESET_ARGS=""
  fi

  echo ">>> [$NAME] cut (remove FFs -> combinational)"
  fault cut -d "$DFF" --clock CK $RESET_ARGS --bypassing VDD=1 --bypassing GND=0 \
    -o "netlists/$NAME.cut.v" "netlists/$NAME.nl.v"

  echo ">>> [$NAME] ATPG + fault simulation"
  fault -c "$MODELS" -v "$V" -r "$R" -m 95 --ceiling "$CEIL" \
    "netlists/$NAME.cut.v" --clock CK $RESET_ARGS --bypassing VDD=1 --bypassing GND=0

  echo ">>> [$NAME] scan chain insertion + verification"
  local SKIP=""
  [ "$HAS_RESET" = "no" ] && SKIP="--skip-synth"
  fault chain --clock CK $RESET_ARGS --bypassing VDD=1 --bypassing GND=0 $SKIP \
    -l "$LIB" -c "$MODELS" -o "netlists/$NAME.chained.v" "netlists/$NAME.nl.v" || true
}

run_circuit s27  DFFSR    yes  20 10 200
run_circuit s298 DFFPOSX1 no   50 30 500
run_circuit s344 DFFPOSX1 no   50 30 500
