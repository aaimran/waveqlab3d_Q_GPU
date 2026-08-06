# waveqlab3d_Q_GPU

This is the standalone workspace for migrating the original `waveqlab3d_Q`
MPI/CPU Fortran solver to NVIDIA GPUs. See the complete design in
[MPI_CPU_to_GPU_Migration_Plan.md](MPI_CPU_to_GPU_Migration_Plan.md) and active
progress in [DEVELOPMENT_STATUS.md](DEVELOPMENT_STATUS.md).

The repository is standalone. It contains its own solver sources, tests,
inputs, CMake helpers, preprocessing tools, and simulation cases. The CPU and
GPU configurations build from the same locally versioned numerical source;
the original sibling `waveqlab3d_Q` repository is not read or modified.

The standalone payload includes:

- `src/`: solver and preprocessor Fortran sources;
- `cmake/` and `conf/`: regression helpers and documentation configuration;
- `tests/` and `test_problems/`: unit and MPI regression cases;
- `inputfile/` and `simulation/`: reference and production inputs;
- `python/` and `auxilary/`: analysis and validation tools;
- `preflight_waveqlab3d_Q.py`: input preflight launcher.

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

If Punakha does not provide an NVHPC module, follow
[PUNAKHA_LOCAL_NVHPC.md](PUNAKHA_LOCAL_NVHPC.md) for a no-sudo installation
under `/work/$USER`.

The installation actually verified on Punakha, including the home-quota
workaround and H100 OpenACC device test, is recorded in
[punakha_nvdia_install.md](punakha_nvdia_install.md).

The NVHPC shutdown segmentation fault found during Q4/Q8 qualification and
its standards-compliant optional-argument fix are documented in
[NVHPC_shutdown_regression_fix.md](NVHPC_shutdown_regression_fix.md).
