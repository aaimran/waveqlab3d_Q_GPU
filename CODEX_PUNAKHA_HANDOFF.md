# Codex handoff: continue WaveQLab3D GPU migration on Punakha

Date: 2026-08-06  
Repository: `/scratch/aimran/waveqlab3d_Q_GPU`  
Branch: `main`  
Handoff baseline: Phase 3 implementation through `92baf7d`

## Purpose of this document

This file is the starting context for a new Codex session running through VS
Code Remote SSH on Punakha. Read this file completely before editing. Then read
the referenced design and status documents in the order listed below.

The objective is to migrate the standalone MPI/CPU Fortran WaveQLab3D solver
to NVIDIA GPUs safely, first on one H100 and later on distributed GPUs. Preserve
the CPU solver as the numerical oracle throughout the migration.

## Non-negotiable repository boundaries

- Work only in `/scratch/aimran/waveqlab3d_Q_GPU`.
- This repository is standalone and contains its own `src/`, inputs, tests,
  CMake helpers, and utilities.
- Do not modify the sibling `waveqlab3d_Q` repository. It is the preserved
  original CPU source/oracle.
- Do not copy fresh files from `waveqlab3d_Q` unless the user explicitly asks.
- Do not split CPU and GPU into separate codebases. CPU and OpenACC builds must
  continue to use the same numerical source.
- Do not enable CUDA-aware MPI yet.
- Do not claim GPU acceleration merely because the `gpu-h100` preset runs.
  At this handoff, OpenACC runtime/device binding is active, but no numerical
  kernel is offloaded.
- Preserve float64 working precision and scientific behavior.
- Make small, gated changes. Build and test after every meaningful step.
- Record every Punakha qualification result in the relevant Markdown report
  and `DEVELOPMENT_STATUS.md`.

## Required reading order

1. `MPI_CPU_to_GPU_Migration_Plan.md`
   - Authoritative 15-phase roadmap, Phases 0 through 14.
2. `DEVELOPMENT_STATUS.md`
   - Current implemented/pending status and recorded qualifications.
3. `PHASE2_SCRATCH_MEMORY_AUDIT.md`
   - Point scratch, persistent face workspaces, FD fixtures, and interface gate.
4. `PHASE2_PERSISTENT_ARRAY_INVENTORY.md`
   - Structural inventory and exact runtime payload accounting.
5. `PHASE3_DEVICE_DATA_OWNERSHIP.md`
   - Explicit leaf residency, host update, transfer, memory, and cleanup gates.
6. `ACCELERATOR_RUNTIME.md`
   - Local-rank discovery, H100 binding, and oversubscription rules.
7. `NVHPC_shutdown_regression_fix.md`
   - Important NVHPC optional-argument correctness fix.
8. `punakha_nvdia_install.md`
   - Actual local NVHPC 26.5 installation and home-quota workaround.
9. `CMakePresets.json` and `src/CMakeLists.txt`
   - Current build variants and source ordering.

Do not rely only on older “Next gate” prose near the top of
`DEVELOPMENT_STATUS.md`; the chronological results near the bottom are more
recent. Reconcile any stale wording you encounter.

## Architecture overview

The executable is built from `src/`. Important ownership and execution files:

- `src/datatypes.f90`: canonical derived types and allocatable ownership.
- `src/domain.f90`: domain initialization, reporting, shutdown, and RK-level
  orchestration.
- `src/block.f90`: per-block initialization and persistent boundary workspace.
- `src/iface.f90`: interface initialization and persistent interface workspace.
- `src/fields.f90`: volume field and rate allocation/update operations.
- `src/material.f90`: elastic and attenuation properties/state.
- `src/pml.f90`: PML auxiliary allocation and initialization.
- `src/RHS_Interior.f90`: active traditional/upwind/upwind-DRP RHS paths.
- `src/JU_xJU_yJU_z6.f90`: generated/large spatial stencil implementation.
- `src/BoundaryConditions.f90`: physical boundary SAT work.
- `src/CouplingForcing.f90` and `src/Interface_Condition.f90`: locked/fault
  interface work.
- `src/time_step.f90`: RK stage orchestration.
- `src/accelerator_runtime_cpu.f90`: CPU runtime implementation.
- `src/accelerator_runtime_openacc.f90`: OpenACC device discovery and binding.
- `src/persistent_memory.f90`: exact allocated payload accounting by category.

The main state is a `domain_type` containing allocatable blocks and interfaces.
Do not attempt an implicit OpenACC deep copy of `domain_type`. Phase 3 requires
explicit traversal and attachment/copying of allocatable leaf arrays.

## Completed roadmap work

### Phase 0: CPU oracle and repository freeze

Complete. The standalone repository and CPU regression baseline exist.

### Phase 1: dual-backend build and accelerator runtime

Complete.

- `cpu-debug` and `cpu-release` presets use the CPU backend.
- `gpu-h100` uses NVHPC/OpenACC with `cc90`.
- Node-local MPI rank is derived using `MPI_Comm_split_type`.
- One local rank binds deterministically to one visible GPU.
- Production GPU oversubscription is rejected with error code 92.
- `WQL3D_ALLOW_GPU_OVERSUBSCRIPTION=1` is test-only.
- CUDA-aware MPI is still disabled.

### Phase 2 numerical, memory, allocation, and scratch-safety gates

The following are complete and qualified with GNU and NVHPC:

- Seventeen point-stencil routines use private fixed nine-value scratch.
- Fifty-three hot-path first-call allocations and shared `save` state were
  removed.
- Active physical-boundary and interface face arrays have persistent explicit
  owners and guarded cleanup.
- Traditional order 6, upwind order 6, and upwind-DRP order 6 fixtures compare
  one-rank and two-rank final state.
- A locked two-block 41-cubed interface oracle verifies nonzero transmission
  from block 1 to block 2 and one-rank/two-rank consistency.
- Structural inventory covers 178 allocatable components.
- Runtime payload accounting reports grid, material/Q, state/rate, PML,
  boundary/work, interface/source, output, maximum host/rank, and predicted
  device/rank bytes.
- GPU capacity enforcement reserves 1 GiB plus 10% and rejects insufficient
  configured capacity before timestepping.
- A transitive 131-procedure source audit and linker allocation tracker prove
  the selected RK paths perform no steady-state heap allocation.
- OpenMP 1/2/4-thread determinism and a four-thread eight-test suite pass.

Important measured examples:

```text
one 41^3 elastic block predicted device payload: 32.334 MiB
one 41^3 Q8 block predicted device payload:      109.961 MiB

locked interface GNU debug:
  block1 max = 2.0699E+03
  block2 max = 1.6389E+03

Punakha locked-interface qualification:
  cpu-release = PASS, 40.40 s
  gpu-h100    = PASS, 41.32 s
```

The H100 timings above are compiler/runtime qualifications, not accelerated
kernel timings.

## Current exact status

Phases 0-3 are complete. Phase 3 explicitly traverses every allocated instance
of all 158 device-policy declarations, retains them across timestepping,
provides an explicit host-update API, validates presence, and deletes leaves in
reverse order. The H100 smoke reconciled 32.334 MiB of inventory/traversal
payload with a 42.000 MiB runtime allocation delta and 9.666 MiB overhead.
Focused H100 coverage passed 11/11 in 105.16 s; CPU oracle coverage passed 7/7
in 30.59 s. NVHPC notifications showed no RK transfer or kernel launch.

No numerical GPU kernel is offloaded yet. Phase 4 is next.

## Exact next implementation task

Offload the smallest low-risk Phase 4 RK vector kernels without changing
numerical results.

Recommended safe design:

1. Port `F%DF = A*F%DF` and `F%F = F%F + dt*F%DF` first, as separate kernels.
2. Preserve a CPU implementation and use the existing persistent data with
   `present` requirements; never add implicit copies.
3. Preserve the x-contiguous vector direction and make gang/vector/collapse
   choices explicit.
4. Add asymmetric local-shape unit tests and a synthetic one-stage/one-step
   rate/state comparison against CPU.
5. Qualify a complete elastic run and then attenuation/PML updates separately.
6. Use NVHPC notification/profiling evidence to prove kernels execute on H100
   and no hidden transfer occurs inside RK.
7. Keep CUDA-aware MPI disabled and do not port the spatial RHS in Phase 4.

## Punakha environment

The verified installation is:

```text
NVHPC=/scratch/aimran/nvidia/hpc_sdk
NVHPC_SDK_ROOT=/scratch/aimran/nvidia/hpc_sdk/Linux_x86_64/26.5
GPU=NVIDIA H100 80GB HBM3
architecture=cc90
```

A typical clean environment is:

```bash
module purge
unset FC F77 F90 FFLAGS I_MPI_ROOT I_MPI_F90 I_MPI_F77 MPI_ROOT MPI_HOME

export NVHPC=/scratch/aimran/nvidia/hpc_sdk
export NVHPC_SDK_ROOT="$NVHPC/Linux_x86_64/26.5"
export PATH="$NVHPC_SDK_ROOT/compilers/bin:$NVHPC_SDK_ROOT/comm_libs/mpi/bin:$PATH"
export LD_LIBRARY_PATH="$NVHPC_SDK_ROOT/compilers/lib:$NVHPC_SDK_ROOT/comm_libs/mpi/lib:${LD_LIBRARY_PATH:-}"

export TMPDIR=/scratch/aimran/tmp
mkdir -p "$TMPDIR"

# Keep NVIDIA compiler configuration out of the quota-limited home directory.
export XDG_CONFIG_HOME=/scratch/aimran/.config
mkdir -p "$XDG_CONFIG_HOME/NVIDIA"
```

Verify before configuring:

```bash
which nvfortran
nvfortran --version
which mpifort
mpifort --show
nvidia-smi
```

Do not allow Intel MPI variables or wrappers to leak into the NVHPC build.

## Configure and build

From the repository root:

```bash
cd /scratch/aimran/waveqlab3d_Q_GPU

cmake --preset cpu-release --fresh
cmake --build --preset cpu-release --parallel 8

cmake --preset gpu-h100 --fresh
cmake --build --preset gpu-h100 --parallel 8
```

If the system CMake is too old, use the installed explicit path previously
verified on Punakha:

```bash
/scratch/aimran/cmake-3.30.2-linux-x86_64/bin/cmake --preset gpu-h100 --fresh
/scratch/aimran/cmake-3.30.2-linux-x86_64/bin/cmake --build --preset gpu-h100 --parallel 8
```

## Core regression commands

For small two-rank tests inside a one-slot interactive allocation:

```bash
export WQL3D_TEST_MPI_OVERSUBSCRIBE=1
```

For the H100 preset only, two test ranks intentionally share the one visible
H100:

```bash
export WQL3D_ALLOW_GPU_OVERSUBSCRIPTION=1
```

All OpenACC simulations also require an explicit per-device capacity. The
verified H100 reports 81559 MiB:

```bash
export WQL3D_GPU_MEMORY_BYTES=85520809984
```

Run the core suite:

```bash
ctest --test-dir build/cpu-release \
  -R 'fq8_effective_response_unit|q8_dynamic_decomposition|q4_dynamic_decomposition|elastic_(traditional|upwind|upwind_drp)_o6_decomposition' \
  --output-on-failure

ctest --test-dir build/gpu-h100 \
  -R 'fq8_effective_response_unit|q8_dynamic_decomposition|q4_dynamic_decomposition|elastic_(traditional|upwind|upwind_drp)_o6_decomposition' \
  --output-on-failure
```

Run the locked interface separately because it takes about 40 seconds per
configuration:

```bash
ctest --test-dir build/cpu-release \
  -R elastic_locked_interface_o6_decomposition \
  --output-on-failure

ctest --test-dir build/gpu-h100 \
  -R elastic_locked_interface_o6_decomposition \
  --output-on-failure
```

Clean the test-only overrides afterward:

```bash
unset WQL3D_ALLOW_GPU_OVERSUBSCRIPTION
unset WQL3D_TEST_MPI_OVERSUBSCRIBE
unset WQL3D_GPU_MEMORY_BYTES
```

## Inventory checks

```bash
python3 -m py_compile scripts/inventory_persistent_arrays.py
python3 scripts/inventory_persistent_arrays.py --check
python3 scripts/inventory_persistent_arrays.py
```

Expected drift-check result at the handoff baseline:

```text
PASS: 178 persistent allocatable components
```

If this count changes, inspect the datatype diff and update the ownership/device
policy deliberately. Do not simply lower the check threshold or ignore parser
failures.

## Test-only versus production behavior

- `WQL3D_TEST_MPI_OVERSUBSCRIBE=1`: permits MPI oversubscription in regression
  harnesses only.
- `WQL3D_ALLOW_GPU_OVERSUBSCRIPTION=1`: permits multiple local test ranks to
  bind to one GPU. Never recommend this for production.
- `WQL3D_ENABLE_CUDA_AWARE_MPI=OFF`: keep this off.
- Production intent remains one MPI rank per visible GPU.

## Git workflow on Punakha

At the start of every Codex task:

```bash
cd /scratch/aimran/waveqlab3d_Q_GPU
git status --short
git branch --show-current
git log -5 --oneline
```

The handoff baseline should be clean at commit `cee9e79`. If newer commits are
present, inspect them before assuming this document is current.

Before pulling, never discard unknown Punakha changes. Review or commit them.
Do not use `git reset --hard` unless the user explicitly requests destructive
replacement.

For each completed gate:

1. Keep the diff focused.
2. Run `git diff --check`.
3. Run relevant CPU tests.
4. Run NVHPC CPU and H100 compiler/runtime tests.
5. Update the status/report documentation.
6. Commit and push so the local backup can follow.

## Scientific qualification rules

A change is not scientifically qualified merely because it compiles.

For every numerical/offload change eventually introduced:

- compare against the frozen CPU result;
- require finite state;
- require nonzero dynamic response where applicable;
- compare one-rank and multi-rank behavior;
- test traditional, upwind, and upwind-DRP where the changed path is shared;
- test PML and no-PML separately when boundary code changes;
- test elastic before attenuation/fault/plastic models;
- record precision and compiler/backend;
- separate correctness timing from performance timing.

Do not weaken tolerances simply to make GPU output pass. Investigate arithmetic
order, synchronization, data residency, and race conditions first.

## Suggested opening prompt for the new Codex session

Paste this into Codex after opening the remote repository:

> Work only in `/scratch/aimran/waveqlab3d_Q_GPU`. Read
> `CODEX_PUNAKHA_HANDOFF.md` completely, then read the referenced plan and
> status documents in its required order. Verify Git status and the Punakha
> NVHPC/MPI environment. Summarize the current migration state and implement
> the smallest safe Phase 4 RK vector-kernel offload using the qualified
> persistent leaf ownership and explicit `present` data. Keep a CPU path, do
> not port the spatial RHS, do not modify `waveqlab3d_Q`, and do not enable
> CUDA-aware MPI. Verify asymmetric kernel tests, CPU/H100 numerical results,
> actual H100 launches, and absence of implicit RK transfers, then update the
> documentation.

## Definition of a successful handoff

The new session understands that:

- the remote Punakha repository is now authoritative;
- Phases 2 and 3 are closed with GNU and NVHPC/H100 evidence;
- exact persistent payload and capacity/headroom accounting already exist;
- low-risk Phase 4 RK vector kernels are the immediate target;
- no numerical GPU kernel is currently offloaded;
- the CPU oracle and single-source CPU/GPU codebase must remain intact;
- every change requires CPU plus NVHPC/H100 regression evidence.
