# Development status

Last updated: 2026-08-06

## Current phase

Phase 1: dual-backend build foundation.

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

## Not implemented yet

- No numerical kernel is offloaded.
- No simulation array is persistent on device.
- CUDA-aware MPI has not been exercised; its option currently records intent.
- No GPU result is qualified for scientific use.

## Next gate

1. Build the standalone `cpu-release` preset on Punakha.
2. Run one identical, deterministic short simulation with `cpu-release` and
   `gpu-h100` in separate output directories.
3. Compare return codes, receiver files, final-state diagnostics, and timing
   metadata; archive the results as the first Punakha oracle.
4. Run the applicable one-rank/two-rank regression subset.
5. Only after equivalence passes, add accelerator runtime reporting and
   node-local MPI-rank/GPU binding.

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

The IEEE signaling warnings printed after preflight occur during the
intentional Fortran `STOP` after `MPI_Finalize`; no timestep was executed.

Standalone-tree verification on 2026-08-06:

- configured and built using only `waveqlab3d_Q_GPU/src`;
- built `waveqlab3d`, `pre_wql3d`, and the fQ8 unit executable;
- passed `fq8_effective_response_unit`;
- passed one-rank preflight using the local `inputfile/test_moment_tensor.in`;
- confirmed the original `waveqlab3d_Q/src/CMakeLists.txt` has no migration
  diff.
