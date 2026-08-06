# Codex handoff: continue WaveQLab3D GPU migration on Punakha

Date: 2026-08-06  
Repository: `/scratch/aimran/waveqlab3d_Q_GPU`  
Branch: `main`  
Handoff baseline commit: `439c4bc Update 7`

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
5. `ACCELERATOR_RUNTIME.md`
   - Local-rank discovery, H100 binding, and oversubscription rules.
6. `NVHPC_shutdown_regression_fix.md`
   - Important NVHPC optional-argument correctness fix.
7. `punakha_nvdia_install.md`
   - Actual local NVHPC 26.5 installation and home-quota workaround.
8. `CMakePresets.json` and `src/CMakeLists.txt`
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

### Phase 2 numerical and scratch-safety gates

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

Phases 0 and 1 are complete.

Phase 2 numerical work, scratch correction, structural inventory, and runtime
payload accounting are complete. Phase 2 is **not yet closed** because these
roadmap gates remain:

1. GPU capacity/headroom preflight with explicit reserve.
2. Evidence that no allocation occurs in steady-state RK stages.
3. Threaded CPU race-safety evidence.
4. Ideally, compare predicted device payload with measured OpenACC allocation
   after the Phase 3 no-kernel data-region smoke test; that final comparison
   naturally straddles Phases 2 and 3.

Do not begin numerical kernel offload until the first three gates are addressed
and recorded.

## Exact next implementation task

Implement GPU capacity/headroom enforcement without changing numerical results.

Recommended safe design:

1. Keep `src/persistent_memory.f90` as the authoritative allocated-payload
   traversal.
2. Add a configurable capacity source:
   - explicit environment override for deterministic tests, such as
     `WQL3D_GPU_MEMORY_BYTES`;
   - later, an NVIDIA runtime query when a portable/reliable interface is added.
3. Define documented reserves rather than treating all reported free memory as
   usable:
   - fixed runtime/MPI reserve;
   - percentage headroom for kernel temporaries and fragmentation;
   - optional user override for controlled experiments.
4. Perform the check after all persistent arrays and output structures are
   initialized but before timestepping/device entry.
5. Report:
   - predicted persistent device payload;
   - configured/detected device capacity;
   - fixed reserve;
   - fractional reserve;
   - usable capacity;
   - remaining headroom;
   - pass/fail decision.
6. Reject insufficient capacity before the first RK step with a dedicated,
   documented diagnostic code.
7. Do not reject CPU runs. CPU builds should report payload but skip GPU
   capacity enforcement.
8. Add deterministic tests that inject a small capacity (must reject) and a
   sufficient capacity (must pass). Tests must not depend on the physical H100
   memory size.

Potential complication: OpenACC does not provide a sufficiently portable
Fortran API for total/free device memory. Prefer an explicit environment value
for the first tested implementation rather than parsing `nvidia-smi` from the
solver. A later small CUDA runtime interoperability layer can supply measured
capacity.

After capacity enforcement, implement allocation evidence. A reasonable first
gate is a source audit/check script that rejects `allocate` or `deallocate`
inside known steady-state call paths, followed by profiler validation on
Punakha. Do not mistake a static audit alone for runtime proof.

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

The handoff baseline should be clean at commit `439c4bc`. If newer commits are
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
> NVHPC/MPI environment. Summarize the current migration state and propose the
> smallest safe implementation for the next Phase 2 gate: deterministic GPU
> capacity/headroom preflight using the existing runtime persistent-memory
> accounting. Do not modify `waveqlab3d_Q`, do not enable CUDA-aware MPI, and
> do not offload numerical kernels yet. Implement only after inspecting the
> relevant runtime/config/error/test patterns, then verify CPU and H100 builds
> and update the documentation.

## Definition of a successful handoff

The new session understands that:

- the remote Punakha repository is now authoritative;
- Phase 2 numerical gates are complete but Phase 2 itself is not closed;
- exact persistent payload accounting already exists;
- capacity/headroom enforcement is the immediate implementation target;
- no numerical GPU kernel is currently offloaded;
- the CPU oracle and single-source CPU/GPU codebase must remain intact;
- every change requires CPU plus NVHPC/H100 regression evidence.
