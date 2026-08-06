# Accelerator runtime and MPI rank-to-GPU binding

Status: implemented; H100 qualification passed  
Date: 2026-08-06

## Purpose

This layer establishes deterministic accelerator ownership before any
WaveQLab3D numerical array is moved to a GPU. CPU and OpenACC builds expose the
same initialization/finalization API.

## Initialization order

```text
MPI_Init
  -> accelerator runtime initialization
  -> input preflight
  -> domain initialization
  -> timestepping
  -> domain cleanup
  -> accelerator runtime finalization
  -> MPI_Finalize
```

Preflight-only execution also initializes and finalizes the runtime cleanly.

## GPU memory capacity preflight

OpenACC simulations require an explicit device-capacity value before the first
RK step:

```bash
export WQL3D_GPU_MEMORY_BYTES=85520809984
```

Use the scheduler-visible device's byte capacity; do not use aggregate memory
across GPUs. The capacity policy reserves 1 GiB for the OpenACC, CUDA, and MPI
runtimes, then reserves another 10% of total capacity for kernel temporaries,
allocator fragmentation, and operational headroom. The predicted persistent
payload must fit in the remainder on every rank.

Controlled experiments may override the reserves:

```bash
export WQL3D_GPU_MEMORY_FIXED_RESERVE_BYTES=1073741824
export WQL3D_GPU_MEMORY_RESERVE_FRACTION=0.10
```

The fixed reserve must be a nonnegative integer byte count and the fraction
must be in `[0,1)`. Missing or malformed capacity configuration emits
`RUN-GPU-MEM-001` and aborts with code 93. Insufficient usable capacity emits
`RUN-GPU-MEM-002` and aborts with code 94. CPU builds continue to report the
predicted payload but skip accelerator-capacity enforcement.

The OpenACC CTest configuration includes deterministic sufficient-capacity and
insufficient-capacity cases. They inject synthetic capacity values and do not
depend on the installed GPU's physical memory size.

## Node-local rank discovery

Each process calls:

```fortran
MPI_Comm_split_type(MPI_COMM_WORLD, MPI_COMM_TYPE_SHARED, ...)
```

The resulting shared-memory communicator supplies `local_rank` and
`local_size`. This works across multiple nodes without assuming that global
MPI rank numbering matches physical node placement.

## GPU selection

The OpenACC backend obtains the visible NVIDIA device count and assigns:

```text
selected_device = local_rank modulo visible_device_count
```

The normal production requirement is one local MPI rank per visible GPU. If
`local_size` exceeds the device count, startup aborts before input parsing or
domain allocation.

For small launch-policy tests only, oversubscription can be enabled with:

```bash
export WQL3D_ALLOW_GPU_OVERSUBSCRIPTION=1
```

This is separate from `WQL3D_TEST_MPI_OVERSUBSCRIBE`, which permits PRRTE to
launch more test ranks than scheduler slots. Neither override should be used
for production performance or scientific runs.

## Startup report

The runtime reports:

- CPU or OpenACC backend;
- whether OpenACC was compiled in;
- CUDA-aware MPI build intent;
- working precision in bits;
- global MPI rank count;
- each rank's node-local rank;
- visible NVIDIA GPU count;
- selected GPU number.

Multi-rank binding lines are printed in global-rank order so launch placement
can be archived and audited.

## Current scope

The runtime calls OpenACC device initialization and shutdown only. It does not
create, copy, attach, or update solver arrays, and it does not offload RK or
RHS kernels. Therefore this layer must not change numerical results.

## Qualification commands on Punakha

One rank and one H100:

```bash
mpirun -np 1 build/gpu-h100/solver/waveqlab3d \
  inputfile/test_anelastic_Q8_dynamic.in
```

Expected binding:

```text
rank 0: local_rank=0, visible_gpus=1, selected_gpu=0
```

Oversubscription rejection test in a one-H100 allocation:

```bash
export WQL3D_TEST_MPI_OVERSUBSCRIBE=1
mpirun --map-by :OVERSUBSCRIBE -np 2 \
  build/gpu-h100/solver/waveqlab3d \
  inputfile/test_anelastic_Q8_dynamic.in
```

Expected: startup abort with error code 92 before simulation initialization.

Test-only two-rank sharing, used solely to repeat the pre-offload decomposition
regression on one H100:

```bash
export WQL3D_TEST_MPI_OVERSUBSCRIBE=1
export WQL3D_ALLOW_GPU_OVERSUBSCRIPTION=1

ctest --test-dir build/gpu-h100 \
  -R 'q8_dynamic_decomposition|q4_dynamic_decomposition' \
  --output-on-failure

unset WQL3D_ALLOW_GPU_OVERSUBSCRIPTION
unset WQL3D_TEST_MPI_OVERSUBSCRIBE
```

Production multi-GPU qualification must instead request one scheduler task and
one GPU for every local MPI rank.

## Punakha H100 results

Verified on 2026-08-06 with NVHPC 26.5 and one H100:

```text
backend: openacc
OpenACC enabled: T
CUDA-aware MPI intent: F
working precision bits: 64
global MPI ranks: 1
rank 0: local_rank=0, visible_gpus=1, selected_gpu=0
```

The one-rank Q8 simulation completed normally:

```text
steps: 5
max|field|:  1.8221E+02
max|memory|: 1.4544E+01
total MPI time: 2.034971116 s
reported simulation elapsed time: 1.816 s
```

With both test-only oversubscription variables enabled, decomposition
regressions passed while two ranks shared the single H100:

```text
q8_dynamic_decomposition  passed, 7.82 s
q4_dynamic_decomposition  passed, 6.79 s
total                      14.61 s
```

This confirms runtime initialization, binding, cleanup, and unchanged
pre-offload numerical behavior. It is not a multi-GPU performance result.

The default oversubscription guard was also verified with two MPI ranks and one
visible H100 while MPI slot oversubscription was enabled. With
`WQL3D_ALLOW_GPU_OVERSUBSCRIPTION` unset, startup reported:

```text
ERROR accelerator runtime: local MPI ranks=2 exceed visible GPUs=1
  Request one GPU per local rank or explicitly set
  WQL3D_ALLOW_GPU_OVERSUBSCRIPTION=1 for tests only.
```

The runtime called `MPI_Abort` with error code 92 before input parsing or domain
allocation. This is the expected negative-test result.

## H100 capacity qualification

Verified on 2026-08-06 with NVHPC 26.5 and one H100. The deterministic 8 GiB
acceptance test and 1 MiB rejection test both passed. A one-rank Q8 run with
`WQL3D_GPU_MEMORY_BYTES=85520809984` reported:

```text
predicted persistent payload:    109.961 MiB
configured device capacity:    81559.000 MiB
fixed reserve:                  1024.000 MiB
fractional reserve:             8155.900 MiB (10%)
usable capacity:               72379.100 MiB
remaining headroom:            72269.139 MiB
decision: PASS
```

The fQ8/Q8/Q4/traditional/upwind/upwind-DRP numerical selection passed 6/6 in
34.23 seconds, with unchanged Q8 final-state diagnostics.
