# Pre-scan versus Post-scan Area Summary

| Circuit | Pre-scan cells | Post-scan cells | Cell overhead | Pre-scan area | Post-scan area | Area overhead |
|---|---:|---:|---:|---:|---:|---:|
| `s27` | 15 | 56 | 273.33% | 3264.00 | 10140.00 | 210.66% |
| `s298` | 75 | 162 | 116.00% | 12284.00 | 25652.00 | 108.82% |
| `s344` | 106 | 263 | 148.11% | 15320.00 | 41480.00 | 170.76% |

## Method

Pre-scan and post-scan netlists were analyzed using Yosys `stat -liberty` with the same OSU035 Liberty library.

The `s298` and `s344` post-scan intermediate wrappers were patched in the build directory and fully technology-mapped before measurement.

Area values are sums of standard-cell areas from the Liberty file. They are mapped cell-area estimates, not post-placement-and-routing silicon area.

The percentage overhead is calculated as:

```text
(post-scan value - pre-scan value) / pre-scan value * 100
```

The large relative overheads are partly caused by the small benchmark sizes and by the inclusion of input and output boundary registers in the generated scan structures.
