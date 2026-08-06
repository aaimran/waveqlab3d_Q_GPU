# Development status

Last updated: 2026-08-04

## Current phase

Phase 1: dual-backend build foundation.

## Implemented

- A standalone copy of the MPI/CPU solver, tests, inputs, and utilities is now
  maintained in this repository; the original `waveqlab3d_Q` is independent.
- Independent CPU debug and release build presets are available.
- An NVHPC/OpenACC H100 preset is available.
- The H100 preset pins the Fortran and MPI compiler to NVHPC's bundled HPC-X
  `mpifort`, preventing accidental linkage to Punakha's Intel MPI environment.
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

1. Run both CPU presets on the target Linux system and freeze reference output.
2. Compile `gpu-h100` with NVHPC, still without GPU numerical directives.
3. Confirm that execution matches the oracle before adding device data.

## Local verification

Verified on 2026-08-04 with GNU Fortran 14.2, Open MPI 5.0.7, and CMake
4.0.2:

- `cpu-debug` configured and built `waveqlab3d`, `pre_wql3d`, and the fQ8 unit
  executable successfully;
- `fq8_effective_response_unit` passed;
- one-rank preflight passed for `inputfile/test_moment_tensor.in`;
- configuration correctly rejected CUDA-aware MPI without OpenACC.

NVHPC and an NVIDIA GPU are unavailable in this local environment, so the H100
compiler and runtime gates remain pending for Punakha.

Standalone-tree verification on 2026-08-06:

- configured and built using only `waveqlab3d_Q_GPU/src`;
- built `waveqlab3d`, `pre_wql3d`, and the fQ8 unit executable;
- passed `fq8_effective_response_unit`;
- passed one-rank preflight using the local `inputfile/test_moment_tensor.in`;
- confirmed the original `waveqlab3d_Q/src/CMakeLists.txt` has no migration
  diff.
