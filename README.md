# Full-Scan Insertion and Stuck-at ATPG on ISCAS'89 Benchmarks

Design-for-Test (DFT) project: converting sequential gate-level netlists into
scan-testable designs, generating stuck-at ATPG patterns, and measuring fault
coverage on standard ISCAS'89 benchmark circuits.

## Toolchain

- **Yosys 0.33** — logic synthesis to a standard cell library
- **[Fault](https://github.com/AUCOHL/Fault)** (`fault-dft` on PyPI) — netlist
  cutting, stuck-at ATPG + fault simulation, scan-chain stitching
- **Icarus Verilog** — gate-level simulation / testbench verification
- **Standard cell library**: `osu035` (350nm, bundled with Fault) — Liberty +
  Verilog cell models

## Flow

```
ISCAS'89 gate-level RTL (behavioral DFF)
        |  fault synth  (Yosys, map to osu035 stdcells)
        v
Synthesized flattened netlist (real DFFSR/DFFPOSX1 cells)
        |  fault cut  (remove FFs -> pure combinational, expose as ports)
        v
Combinational netlist  ---->  fault atpg  ---->  stuck-at fault coverage,
                                                  compacted test vectors
        |  fault chain (on the pre-cut synthesized netlist)
        v
Scan-inserted netlist (internal scan chain + boundary scan register)
        |  Icarus Verilog testbench
        v
shift-in -> capture -> shift-out verification
```

Full commands: [`scripts/run_pipeline.sh`](scripts/run_pipeline.sh).

## Circuits

Netlists sourced directly from `AUCOHL/Fault`'s bundled ISCAS'89 set
(`Benchmarks/ISCAS_89/*.v`), which are already gate-level Verilog (no manual
`.bench` parsing needed).

## Results

| Circuit | FF count | Fault sites | Coverage (PRNG ATPG) | Compacted patterns | Scan chain (internal / boundary / total) |
|---|---|---|---|---|---|
| s27  | 3  | —   | 86.67% (hit vector ceiling of 200) | 6  | 3 / 5 / 8 |
| s298 | 14 | 244 (61 gates, 40 ports) | 99.18% | 11 | 14 / 9 / 23 |
| s344 | 15 | 346 (91 gates, 53 ports) | 98.84% | 12 | 15 / 20 / 35 |

Raw tool output backing these numbers is kept per-circuit under `results/<circuit>/`.

**Note on s27's coverage:** s27 is small enough that the PRNG-based ATPG hit
the vector ceiling (200) before reaching the 95% target set in
`run_pipeline.sh`; 86.67% is the actual measured coverage at that ceiling, not
a target. Raising the ceiling or switching the generator to Atalanta/Quaigh
(`fault atpg -g Atalanta ...`) would push this higher — left as a documented
follow-up rather than tuned to look better.

## Scan-chain verification (shift-in / capture / shift-out)

For **s27**, Fault's own auto-generated Icarus Verilog testbench
(`results/s27/s27_scan_tb.sv`) shifts a known bit pattern through the chain,
captures, and shifts it back out. Simulation log
(`results/s27/s27_scan_tb_sim.log`):

```
Success: expected 00010101 got 00010101
```

**For s298 / s344**: these circuits have no top-level reset port in the
original ISCAS'89 netlist. Fault's internal auto-verification step assumes a
reset signal exists and fails during testbench elaboration (signal name
mismatch — a real limitation encountered while running the tool, not a bug
in this repo's scripts; worked around with `--skip-synth`). The scan-chain
netlist itself (`results/s298/s298_postscan.v`, `results/s344/s344_postscan.v`)
is still correctly generated, including the scan-cell order embedded as JSON
metadata in the file header. Writing a standalone testbench for the no-reset
case is the next step (see below).

## Area overhead

Pre-scan cell counts are visible in the Yosys synthesis logs
(`fault synth` stdout, captured when running `scripts/run_pipeline.sh`).
Post-scan area comparison (via `report_design_area` equivalent through Yosys
`stat`) is a planned addition once the no-reset scan-chain testbench issue
above is resolved.

## Repo structure

```
benchmarks/        original ISCAS'89 gate-level Verilog (from AUCOHL/Fault)
tech/osu035/       standard cell library (Liberty + Verilog models)
netlists/          intermediate synth/cut/chain outputs
results/<circuit>/ pre-scan netlist, cut netlist, ATPG report (JSON),
                    post-scan netlist, testbench + sim log (where available)
scripts/           run_pipeline.sh - exact reproducible commands
```

## Known limitations / next steps

- s298 / s344 scan-chain testbench verification not yet automated (see above).
- s5378 not yet run (larger circuit, planned).
- ATPG uses Fault's internal PRNG generator; Atalanta/Quaigh backend not yet
  compared (would give a second, algorithmically different coverage number
  for cross-checking).
- Area overhead (pre vs. post scan, single vs. multiple scan chains) not yet
  tabulated.
