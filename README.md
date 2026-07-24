# Full-Scan Insertion and Stuck-at ATPG on ISCAS'89 Benchmarks

A Design-for-Test learning project that converts sequential ISCAS'89 benchmark
circuits into scan-testable designs, generates stuck-at test patterns, performs
fault simulation, and independently verifies the generated scan structures.

## Project Scope

This repository focuses on:

- standard-cell mapping of sequential benchmark circuits;
- sequential-netlist cutting for combinational ATPG;
- single stuck-at fault simulation and test-pattern generation;
- scan-chain insertion and stitching;
- independent scan-chain verification using self-checking testbenches;
- simulation-based functional-mode regression;
- automated ATPG and mapped-area summaries;
- reproducible result collection and analysis.

Fault provides the underlying synthesis integration, netlist cutting,
test-pattern generation, fault simulation, pattern compaction, and scan-chain
stitching.

The project-authored work in this repository includes:

- flow automation and fail-safe status reporting;
- custom scan verification;
- debugging and patching of generated wrappers;
- golden-model development for functional capture checking;
- simulation-based pre-scan versus post-scan regression;
- automated coverage and area summarization;
- result organization and technical analysis.

## Toolchain

- **Yosys** — logic synthesis, technology mapping, and cell-area reporting
- **Fault (`fault-dft==0.9.4`)** — sequential-netlist cutting, stuck-at ATPG,
  fault simulation, test-pattern compaction, and scan-chain stitching
- **Icarus Verilog** — gate-level simulation and self-checking verification
- **OSU035 standard-cell library** — Liberty data and Verilog functional models
- **Python 3** — wrapper patching, generated tests, and result summarization

Python dependency:

```text
requirements.txt
```

## DFT Flow

```text
ISCAS'89 sequential gate-level Verilog
        |
        | fault synth
        v
Technology-mapped sequential netlist
        |
        +----------------------------------+
        |                                  |
        | fault cut                        | fault chain
        v                                  v
Combinational cut netlist          Scan-inserted netlist
        |                                  |
        | fault ATPG                       | custom Icarus regressions
        v                                  v
Stuck-at test patterns,             serial scan integrity,
fault simulation,                   shift-capture-shift,
and coverage reports                and functional-mode checks
```

The end-to-end flow is provided in:

```text
scripts/run_pipeline.sh
```

The pipeline:

- checks required tools and input files;
- stops on synthesis, cut, or ATPG failure;
- records scan-tool exit status;
- distinguishes a missing scan artifact from a generated artifact whose
  tool-generated verification wrapper failed;
- writes one status file per circuit under `results/<circuit>/`.

## Benchmark Circuits

The current project evaluates three circuits from the ISCAS'89 sequential
benchmark set:

- `s27`
- `s298`
- `s344`

## ATPG Results

| Circuit | Fault sites | Total SA faults | Detected | Undetected | Measured coverage | Compacted patterns |
|---|---:|---:|---:|---:|---:|---:|
| `s27` | 45 | 90 | 78 | 12 | 86.67% | 6 |
| `s298` | 244 | 488 | 484 | 4 | 99.18% | 11 |
| `s344` | 346 | 692 | 684 | 8 | 98.84% | 12 |

Each enumerated fault site contributes two single stuck-at faults:

```text
stuck-at-0
stuck-at-1
```

Coverage is calculated as:

```text
detected single stuck-at faults / total enumerated single stuck-at faults
```

The table is generated and cross-checked by:

```bash
python3 scripts/summarize_atpg.py
```

Generated summaries:

```text
results/atpg_summary.csv
results/atpg_summary.md
```

The summary script:

1. reads the fault-site count and tool-reported coverage from ATPG logs;
2. reads the canonical compacted ATPG reports;
3. deduplicates detected stuck-at faults across all compacted patterns;
4. calculates detected, undetected, and total stuck-at faults;
5. verifies that calculated coverage matches the coverage reported by Fault;
6. writes CSV and Markdown summaries.

## Fault-Coverage Interpretation

The reported coverage values are results from the configured PRNG-based ATPG
flow. They are not manually selected target values.

For `s27`, the generator reached the configured vector ceiling before reaching
the requested target coverage.

Increasing the vector ceiling or using another ATPG backend may improve the
measured coverage. The remaining faults have not been independently classified
as detectable, redundant, or untestable.

This repository does not claim that PRNG pattern generation is equivalent to a
deterministic commercial ATPG flow.

## Scan Architecture

The generated scan structures contain:

- tool-generated input boundary registers;
- internal scan flip-flops;
- tool-generated output boundary registers;
- serial scan input and output ports;
- scan shift control.

| Circuit | Input boundary registers | Internal scan FFs | Output boundary registers | Total scan length |
|---|---:|---:|---:|---:|
| `s27` | 4 | 3 | 1 | 8 |
| `s298` | 3 | 14 | 6 | 23 |
| `s344` | 9 | 15 | 11 | 35 |

## Independent Scan Verification

Independent self-checking regressions are provided in addition to the
testbenches generated by Fault.

### s27: True Shift-Capture-Shift Verification

The custom testbench:

```text
verification/s27_scan_capture_tb.sv
```

performs three distinct phases:

1. shifts a known serial stream into the complete scan chain;
2. deasserts `shift` and applies one functional capture pulse;
3. re-enables shifting and unloads the captured response.

The expected captured response is calculated independently by:

```text
verification/s27_golden_comb.sv
```

The regression checks that:

- the unloaded response matches the golden combinational model;
- the captured response differs from the original shift-in stream;
- all three phases complete without simulation failure.

Result log:

```text
results/s27/s27_scan_capture.log
```

Expected final status:

```text
SHIFT-CAPTURE-SHIFT PASS
```

### s298 and s344: Serial Scan-Chain Integrity

The generated intermediate wrappers for `s298` and `s344` declare a reset
input internally but omit it from the top-level module port list.

The script:

```text
scripts/generate_scan_shift_test.py
```

creates patched build copies and self-checking testbenches without modifying
the original generated netlists.

The generated tests:

1. create a deterministic non-trivial serial pattern;
2. shift the pattern through the complete scan chain;
3. unload the chain;
4. compare the observed serial stream against the expected stream.

Result logs:

```text
results/s298/s298_scan_shift.log
results/s344/s344_scan_shift.log
```

Both regressions report:

```text
SCAN SHIFT PASS
```

These tests verify serial scan-chain connectivity and shift operation. They do
not currently claim independent functional-capture verification for `s298` or
`s344`.

## s27 Functional-Mode Regression

A simulation-based functional regression compares the technology-mapped
pre-scan design against the scan-inserted design while the latter is held in
functional mode.

The self-checking testbench is:

```text
verification/s27_functional_equivalence_tb.sv
```

The complete regression can be reproduced with:

```bash
bash scripts/run_s27_functional_regression.sh
```

The runner:

1. creates a build-only copy of the pre-scan netlist whose top module is
   renamed to `s27_prescan`;
2. compiles the pre-scan and post-scan designs into the same simulation;
3. holds the post-scan design in functional mode with `test=0` and `shift=0`;
4. applies the same deterministic pseudo-random input sequence to both
   designs;
5. compares their outputs before and after each functional clock pulse for
   1,000 cycles.

Recorded result:

```text
results/s27/s27_functional_equivalence.log
```

Expected final status:

```text
FUNCTIONAL REGRESSION PASS: 1000 cycles
```

This is a simulation-based regression, not a formal equivalence proof.

## Verification Status

| Check | s27 | s298 | s344 |
|---|---|---|---|
| Technology mapping | Completed | Completed | Completed |
| Sequential-netlist cutting | Completed | Completed | Completed |
| Stuck-at ATPG | Completed | Completed | Completed |
| Fault simulation | Completed | Completed | Completed |
| Scan-chain insertion | Completed | Completed | Completed |
| Serial scan integrity | Pass | Pass | Pass |
| Independent functional capture | Pass | Not yet implemented | Not yet implemented |
| Simulation-based functional regression | Pass | Not yet implemented | Not yet implemented |
| Formal equivalence | Not performed | Not performed | Not performed |

## Pipeline Status

Each pipeline run writes:

```text
results/<circuit>/pipeline_status.txt
```

Current status interpretation:

- `s27` reports a complete pipeline pass, including the verification generated
  by Fault.
- `s298` and `s344` generate post-scan intermediate artifacts, but the
  tool-generated verification wrappers fail to compile because of the reset
  port-list issue.
- Their status files explicitly require the independent custom scan
  regressions rather than silently ignoring the wrapper failure.

Typical status values are:

```text
PIPELINE_STATUS=PASS
PIPELINE_STATUS=PASS_WITH_WRAPPER_WORKAROUND
```

## Pre-scan versus Post-scan Area

The project compares technology-mapped pre-scan and post-scan netlists using
Yosys `stat -liberty` with the same OSU035 Liberty library.

| Circuit | Pre-scan cells | Post-scan cells | Cell overhead | Pre-scan area | Post-scan area | Area overhead |
|---|---:|---:|---:|---:|---:|---:|
| `s27` | 15 | 56 | 273.33% | 3264.00 | 10140.00 | 210.66% |
| `s298` | 75 | 162 | 116.00% | 12284.00 | 25652.00 | 108.82% |
| `s344` | 106 | 263 | 148.11% | 15320.00 | 41480.00 | 170.76% |

The percentage overhead is calculated as:

```text
(post-scan value - pre-scan value) / pre-scan value * 100
```

The `s298` and `s344` post-scan intermediate wrappers are patched only in the
ignored build directory and fully technology-mapped before measurement.

The summaries are generated from Yosys analysis logs by:

```bash
python3 scripts/summarize_area.py
```

Generated result files:

```text
results/area_summary.csv
results/area_summary.md
```

The reported area values are sums of standard-cell areas defined in the
Liberty library. They are mapped cell-area estimates, not post-placement-and-
routing silicon area.

The large relative overheads are influenced by the small benchmark sizes and
by the inclusion of input and output boundary registers in the generated scan
structures.

## Boundary-Register Terminology

The input and output boundary registers generated by the scan-chain stage are
part of this repository's tool-generated scan-test structure.

This project does not implement an IEEE 1149.1 JTAG Test Access Port
controller.

## Repository Structure

```text
benchmarks/
    Original ISCAS'89 sequential benchmark circuits

tech/osu035/
    Liberty file and Verilog standard-cell models

netlists/
    Synthesized, cut, ATPG, and scan-chain artifacts

verification/
    Independent golden models and self-checking testbenches

scripts/
    DFT pipeline, verification runners, wrapper patching,
    ATPG summary, and area summary scripts

results/
    Project-level ATPG and area summaries

results/s27/
    ATPG report, pre-scan/post-scan artifacts, pipeline status,
    scan-capture log, and functional-regression log

results/s298/
    ATPG report, pre-scan/post-scan artifacts, pipeline status,
    and scan-integrity log

results/s344/
    ATPG report, pre-scan/post-scan artifacts, pipeline status,
    and scan-integrity log

build/
    Patched netlists, generated testbenches, simulation binaries,
    Yosys logs, mapped analysis netlists, and waveforms;
    intentionally ignored by Git
```

## Environment Setup

Create and activate a Python virtual environment:

```bash
python3 -m venv .venv
source .venv/bin/activate
```

Install the pinned Fault version:

```bash
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

Verify the tools:

```bash
fault --version
yosys -V
iverilog -V
python3 --version
```

## Running the Core Pipeline

```bash
mkdir -p build/logs
set -o pipefail

bash scripts/run_pipeline.sh 2>&1   | tee build/logs/full_pipeline.log

pipeline_rc=${PIPESTATUS[0]}
echo "Pipeline exit code: $pipeline_rc"
```

Inspect circuit status:

```bash
for circuit in s27 s298 s344; do
    echo "===== $circuit ====="
    cat "results/$circuit/pipeline_status.txt"
done
```

## Reproducing the Scan Tests

### s27 Shift-Capture-Shift

Compile:

```bash
mkdir -p build/s27 results/s27

iverilog -g2012   -s tb_s27_scan_capture   -o build/s27/s27_scan_capture.vvp   tech/osu035/osu035_stdcells.v   netlists/s27.chained.v   verification/s27_golden_comb.sv   verification/s27_scan_capture_tb.sv
```

Run:

```bash
vvp build/s27/s27_scan_capture.vvp   | tee results/s27/s27_scan_capture.log
```

Expected result:

```text
SHIFT-CAPTURE-SHIFT PASS
```

### s298 Serial Scan Integrity

Generate the patched build copy and testbench:

```bash
mkdir -p build/s298 results/s298

python3 scripts/generate_scan_shift_test.py   --circuit s298   --netlist netlists/s298.chain-intermediate.v   --outdir build/s298
```

Compile:

```bash
iverilog -g2012   -s tb_s298_scan_shift   -o build/s298/s298_scan_shift.vvp   tech/osu035/osu035_stdcells.v   build/s298/s298_postscan_patched.v   build/s298/s298_scan_shift_tb.sv
```

Run:

```bash
vvp build/s298/s298_scan_shift.vvp   | tee results/s298/s298_scan_shift.log
```

Expected result:

```text
SCAN SHIFT PASS
```

### s344 Serial Scan Integrity

Generate the patched build copy and testbench:

```bash
mkdir -p build/s344 results/s344

python3 scripts/generate_scan_shift_test.py   --circuit s344   --netlist netlists/s344.chain-intermediate.v   --outdir build/s344
```

Compile:

```bash
iverilog -g2012   -s tb_s344_scan_shift   -o build/s344/s344_scan_shift.vvp   tech/osu035/osu035_stdcells.v   build/s344/s344_postscan_patched.v   build/s344/s344_scan_shift_tb.sv
```

Run:

```bash
vvp build/s344/s344_scan_shift.vvp   | tee results/s344/s344_scan_shift.log
```

Expected result:

```text
SCAN SHIFT PASS
```

## Reproducing the Functional Regression

```bash
bash scripts/run_s27_functional_regression.sh
```

Expected result:

```text
FUNCTIONAL REGRESSION PASS: 1000 cycles
[PASS] s27 functional-mode regression
```

## Generating Result Summaries

ATPG summary:

```bash
python3 scripts/summarize_atpg.py
```

Area summary:

```bash
python3 scripts/summarize_area.py
```

Generated outputs:

```text
results/atpg_summary.csv
results/atpg_summary.md
results/area_summary.csv
results/area_summary.md
```

## Generated-Artifact Policy

Files under `netlists/` and parts of `results/` may be generated by Fault or
Yosys.

Custom verification files and scripts are kept separately so original
tool-generated artifacts remain distinguishable from project-authored code.

Patched copies of generated wrappers are created only under `build/`, leaving
the committed generated netlists unchanged.

Simulation binaries, patched copies, mapped analysis netlists, temporary parser
files, waveforms, and local virtual environments are ignored by Git.

## Current Limitations

- Independent functional shift-capture-shift verification is currently
  implemented only for `s27`.
- `s298` and `s344` have passing serial scan-integrity regressions but no
  independent golden functional-capture models.
- Simulation-based functional regression has been completed for `s27`;
  equivalent regressions have not yet been implemented for `s298` and `s344`.
- Formal equivalence checking has not been performed.
- Remaining undetected faults have not been classified as detectable,
  redundant, or untestable.
- ATPG currently uses Fault's PRNG generator; another ATPG backend has not yet
  been compared.
- Area results are Liberty-based mapped cell-area estimates and do not include
  placement, routing, clock-tree, congestion, or physical-design overhead.
- No IEEE 1149.1 JTAG TAP implementation is included.
- No silicon sign-off flow is claimed.

## Planned Extensions

- Extend independent functional-capture verification to `s298` and `s344`.
- Extend simulation-based functional-mode regression to `s298` and `s344`.
- Compare PRNG-based generation against another ATPG backend.
- Classify remaining faults where possible.
- Compare scan architectures with fewer or no boundary registers.
- Add physical-design estimates when an appropriate open PDK flow is
  available.
- Add an automated regression workflow.
- Add third-party attribution and licensing notices.

## Project Ownership

Fault provides the underlying synthesis integration, sequential-netlist
cutting, fault simulation, test-pattern generation, compaction, and scan-chain
stitching.

This repository focuses on constructing a reproducible DFT flow around those
tools, independently validating generated scan structures, debugging wrapper
generation issues, analyzing ATPG and mapped-area results, and documenting
technical limitations honestly.
