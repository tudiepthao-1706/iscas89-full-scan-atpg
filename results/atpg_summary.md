# ATPG Summary

Generated from the canonical compacted ATPG reports under `results/<circuit>/` and the ATPG execution logs under `build/logs/<circuit>/atpg.log`.

Each enumerated fault site contributes two single stuck-at faults: stuck-at-0 and stuck-at-1.

| Circuit | Fault sites | Total SA faults | Detected | Undetected | Coverage | Compacted patterns |
|---|---:|---:|---:|---:|---:|---:|
| `s27` | 45 | 90 | 78 | 12 | 86.67% | 6 |
| `s298` | 244 | 488 | 484 | 4 | 99.18% | 11 |
| `s344` | 346 | 692 | 684 | 8 | 98.84% | 12 |

## Interpretation

- Coverage is calculated as detected single stuck-at faults divided by total enumerated single stuck-at faults.
- Detected faults are deduplicated across all compacted test patterns.
- Undetected does not automatically mean untestable or redundant.
- The compacted pattern count is read from the canonical committed ATPG report.
- PRNG-based ATPG may produce different pattern sets or compaction results across separate runs.
