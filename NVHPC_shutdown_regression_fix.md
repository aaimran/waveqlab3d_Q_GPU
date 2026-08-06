# NVHPC shutdown regression: diagnosis and fix

Date: 2026-08-06  
Platform: Punakha DGX, NVIDIA H100 80 GB  
Compiler: NVIDIA HPC SDK 26.5  
MPI: NVHPC HPC-X/Open MPI 5  
Status: fixed and locally regression-tested

## Summary

The Q4 and Q8 dynamic regression simulations completed every timestep and
printed valid final-state diagnostics, but the process then terminated with a
segmentation fault inside `mpi3dbasic_finish_mpi_`.

The failure was not caused by Q4, Q8, OpenACC, an H100 kernel, or MPI domain
decomposition. It was a Fortran standards-conformance defect in optional
argument handling during normal shutdown.

## Affected configurations

The same failure occurred in both standalone NVHPC builds:

- `cpu-release`: NVHPC with OpenACC disabled;
- `gpu-h100`: NVHPC with OpenACC compilation enabled but no numerical kernels
  offloaded.

The isolated `fq8_effective_response_unit` passed. Both Q4 and Q8 application
runs failed only after producing their final-state results.

## Numerical evidence before the failure

The one-rank Q8 case completed five timesteps and reported:

```text
Q8 final state: max|field|= 1.8221E+02, max|memory|= 1.4544E+01
```

The one-rank Q4 case completed five timesteps and reported:

```text
Q4 final state: max|field|= 1.8221E+02, max|memory|= 1.1049E+01
```

The debug traceback then located the fault at:

```text
mpi3dbasic_finish_mpi_
MAIN_
main
```

This established that time integration and final-state diagnostics had
finished before the fault.

## Root cause

`finish_mpi` accepted an optional logical argument:

```fortran
logical, intent(in), optional :: report_timing
```

The original condition was:

```fortran
if (is_master() .and. (.not.present(report_timing) .or. report_timing)) then
```

This expression assumes short-circuit evaluation: when `report_timing` is
absent, it assumes `.not.present(report_timing)` will prevent evaluation of the
second operand.

Fortran does not guarantee short-circuit evaluation for `.and.` or `.or.`.
NVHPC therefore remained free to evaluate `report_timing` even when the
optional argument was absent. Accessing the absent argument resulted in a null
dereference and segmentation fault.

GNU Fortran happened not to expose the defect in the previously tested path,
but its behavior did not make the original expression standards-compliant.

## Correction

The optional argument is now resolved in a separate statement:

```fortran
logical :: do_report

do_report = .true.
if (present(report_timing)) do_report = report_timing

if (is_master() .and. do_report) then
```

The corrected code never references `report_timing` unless `present()` has
already returned true.

The change affects only shutdown timing output. It does not modify:

- fields or material state;
- Q4, Q8, or fQ8 equations;
- Runge-Kutta integration;
- PML;
- sources or receivers;
- halo exchange or domain decomposition;
- OpenACC data or kernels.

## Verification

After applying the fix, the standalone GNU debug build passed:

```text
fq8_effective_response_unit    Passed
q8_dynamic_decomposition       Passed
q4_dynamic_decomposition       Passed

100% tests passed, 0 tests failed
```

The regression command was:

```bash
ctest --preset cpu-debug \
  -R 'fq8_effective_response_unit|q8_dynamic_decomposition|q4_dynamic_decomposition' \
  --output-on-failure
```

The required Punakha confirmation is:

```bash
cmake --build --preset cpu-release --parallel 8
cmake --build --preset gpu-h100 --parallel 8

ctest --test-dir build/cpu-release \
  -R 'fq8_effective_response_unit|q8_dynamic_decomposition|q4_dynamic_decomposition' \
  --output-on-failure

ctest --test-dir build/gpu-h100 \
  -R 'fq8_effective_response_unit|q8_dynamic_decomposition|q4_dynamic_decomposition' \
  --output-on-failure
```

Both NVHPC configurations must pass before the GPU migration advances to
accelerator runtime initialization or numerical kernel offload.

### One-slot interactive allocations

After the shutdown fix, Punakha confirmed that the one-rank Q4 and Q8 runs
completed normally. Their two-rank launches were initially rejected by PRRTE
because the interactive allocation exposed only one MPI slot. This is a
scheduler resource issue, not a solver failure.

For these small decomposition tests only, the harness supports:

```bash
export WQL3D_TEST_MPI_OVERSUBSCRIBE=1
```

It adds HPC-X/Open MPI option `--map-by :OVERSUBSCRIBE`. Production simulations
must not use this test override; request the required Slurm tasks and CPUs
instead.

### Punakha confirmation

The corrected builds were rerun on Punakha on 2026-08-06:

| Configuration | fQ8 unit | Q8 1/2-rank | Q4 1/2-rank | Total |
|---|---:|---:|---:|---:|
| `cpu-release` | pass | pass, 7.02 s | pass, 5.90 s | 12.93 s |
| `gpu-h100` | pass | pass, 7.03 s | pass, 5.97 s | 13.01 s |

This closes the NVHPC shutdown regression and the Phase 1 Q4/Q8 decomposition
gate. No numerical GPU kernel was active in this baseline.

## General coding rule

Optional Fortran arguments must not be referenced in compound Boolean
expressions that depend on short-circuit evaluation. Use a separate
`if (present(argument))` statement before reading the argument.

The source tree was also searched for similar compound `present()` patterns.
No second absent-optional dereference of this form was identified.
