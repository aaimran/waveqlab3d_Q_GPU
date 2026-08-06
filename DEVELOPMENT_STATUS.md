# Development status

Last updated: 2026-08-06

## Current phase

Phase 1 compiler and MPI baseline: complete. Accelerator runtime and
deterministic rank-to-GPU binding are implemented; H100 qualification is
pending.

## Implemented

- A standalone copy of the MPI/CPU solver, tests, inputs, and utilities is now
  maintained in this repository; the original `waveqlab3d_Q` is independent.
- Independent CPU debug and release build presets are available.
- An NVHPC/OpenACC H100 preset is available.
- The H100 preset pins compilation to `nvfortran` and MPI discovery to NVHPC's
  bundled HPC-X `mpifort`, preventing accidental Intel MPI linkage.
- CUDA-aware MPI is a separate opt-in and requires OpenACC.
- GPU architecture and CPU-source location are configurable.
- GNU builds accept the generated stencil module's lines beyond column 132;
  this is a compile-only portability setting and does not alter arithmetic.
- CPU and OpenACC accelerator-runtime implementations share one API.
- Startup derives node-local rank and size with `MPI_Comm_split_type`.
- OpenACC assigns devices deterministically from node-local rank and rejects
  GPU oversubscription by default.
- Ordered startup reporting records backend, precision, CUDA-aware MPI intent,
  visible devices, and per-rank GPU selection.

## Not implemented yet

- No numerical kernel is offloaded.
- No simulation array is persistent on device.
- CUDA-aware MPI has not been exercised; its option currently records intent.
- No GPU result is qualified for scientific use.

## Next gate

1. Add accelerator runtime reporting without moving numerical arrays.
2. Derive node-local rank with `MPI_Comm_split_type(MPI_COMM_TYPE_SHARED)`.
3. Bind one local MPI rank to one visible GPU and reject oversubscription by
   default.
4. Report backend, global/local rank, device count, selected GPU, precision,
   MPI implementation, and CUDA-aware MPI intent.
5. Repeat the CPU/OpenACC Q4/Q8 regressions and a short elastic run.

## Local verification

Verified on 2026-08-04 with GNU Fortran 14.2, Open MPI 5.0.7, and CMake
4.0.2:

- `cpu-debug` configured and built `waveqlab3d`, `pre_wql3d`, and the fQ8 unit
  executable successfully;
- `fq8_effective_response_unit` passed;
- one-rank preflight passed for `inputfile/test_moment_tensor.in`;
- configuration correctly rejected CUDA-aware MPI without OpenACC.

Punakha H100 compiler verification completed on 2026-08-06:

- NVIDIA HPC SDK 26.5 installed without sudo under `/scratch/aimran`;
- OpenACC runtime detected one H100 using `-acc=gpu -gpu=cc90`;
- standalone `gpu-h100` configuration selected NVHPC 26.5 and bundled HPC-X
  MPI, with no Intel MPI linkage;
- `waveqlab3d`, `pre_wql3d`, and the fQ8 unit executable built successfully;
- `fq8_effective_response_unit` passed;
- one-rank preflight for `inputfile/test_moment_tensor.in` passed.

NVHPC regression diagnosis found and corrected a standards-conformance defect
in `finish_mpi`: a compound logical expression referenced the absent optional
`report_timing` argument and depended on non-guaranteed short-circuit
evaluation. Q4 and Q8 both completed all timesteps and printed correct final
state diagnostics before NVHPC faulted during normal shutdown. The corrected
code resolves the optional argument before entering the compound condition.

Post-fix Punakha runs confirmed successful one-rank Q4 and Q8 completion. The
remaining two-rank test attempts were rejected before launch because the
interactive allocation advertised one MPI slot. The regression harness now
offers explicit test-only oversubscription through
`WQL3D_TEST_MPI_OVERSUBSCRIBE=1`; production launch behavior is unchanged.

Punakha post-fix qualification completed on 2026-08-06:

```text
cpu-release: fQ8 unit pass; Q8 pass (7.02 s); Q4 pass (5.90 s); total 12.93 s
gpu-h100:    fQ8 unit pass; Q8 pass (7.03 s); Q4 pass (5.97 s); total 13.01 s
```

All six selected checks passed. Each Q4/Q8 decomposition test compares the
formatted final field and memory diagnostics from one-rank and two-rank runs.
No numerical GPU kernel was active during this compiler-baseline gate.

Accelerator-runtime CPU verification completed locally on 2026-08-06:

- standalone GNU debug build passed;
- fQ8, Q8 decomposition, and Q4 decomposition tests all passed;
- preflight reported CPU backend, 64-bit working precision, one node-local
  rank, OpenACC disabled, and CUDA-aware MPI intent disabled.

OpenACC runtime compilation, H100 binding, and oversubscription rejection are
pending Punakha verification.

The IEEE signaling warnings printed after preflight occur during the
intentional Fortran `STOP` after `MPI_Finalize`; no timestep was executed.

Standalone-tree verification on 2026-08-06:

- configured and built using only `waveqlab3d_Q_GPU/src`;
- built `waveqlab3d`, `pre_wql3d`, and the fQ8 unit executable;
- passed `fq8_effective_response_unit`;
- passed one-rank preflight using the local `inputfile/test_moment_tensor.in`;
- confirmed the original `waveqlab3d_Q/src/CMakeLists.txt` has no migration
  diff.
