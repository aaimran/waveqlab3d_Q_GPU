# waveqlab3d_Q_GPU

This is the controlled workspace for migrating the sibling `waveqlab3d_Q`
MPI/CPU Fortran solver to NVIDIA GPUs. See the complete design in
[MPI_CPU_to_GPU_Migration_Plan.md](MPI_CPU_to_GPU_Migration_Plan.md) and active
progress in [DEVELOPMENT_STATUS.md](DEVELOPMENT_STATUS.md).

The initial build is an overlay: it compiles the unchanged sibling CPU source
tree as the numerical oracle. A file is added locally only when a migration
phase needs to modify it, keeping accelerator changes explicit and auditable.

## CPU oracle

```bash
cmake --preset cpu-debug
cmake --build --preset cpu-debug --parallel
ctest --preset cpu-debug
```

Use `cpu-release` for the optimized reference build.

## Initial H100 compiler baseline

Load NVHPC with an MPI-enabled `nvfortran`, then run:

```bash
cmake --preset gpu-h100
cmake --build --preset gpu-h100 --parallel
```

This enables OpenACC compilation for compute capability 9.0, but no numerical
kernel is offloaded yet. The `gpu-h100-cuda-aware-mpi` preset is reserved for
the later distributed phase and must not be used for scientific production
until the staged-host MPI path passes its qualification gates.
