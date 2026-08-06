# WaveQLab3D-Q: safe migration from MPI/CPU to single and distributed GPUs

Date: 2026-08-04  
Status: implementation plan based on the current `waveqlab3d_Q/src` tree  
Target: NVIDIA H100-class GPUs, initially one DGX node and later multiple nodes

## 1. Objective and safety policy

Migrate the existing double-precision MPI Fortran solver to GPUs without
rewriting its numerical methods or invalidating its CPU results.

The migration must preserve:

- the existing MPI/CPU executable as a reference and fallback;
- the nine-field elastic velocity-stress formulation;
- the five-stage Kennedy-Carpenter low-storage RK4 sequence;
- traditional, upwind, and upwind-DRP finite differences;
- curvilinear metrics and SBP/SAT boundary treatment;
- compact face-local CFS ADE-PML;
- moment sources and station output;
- anelastic Q models;
- multi-block interfaces, friction, and plasticity as later qualification
  stages;
- existing input-file behavior unless an explicit accelerator option is used.

No phase may combine a data-layout change, a physics change, and a communication
change. Each must be qualified independently against the preceding version.

## 2. Source audit

### 2.1 Scale and structure

The current source tree contains approximately 53,750 lines of Fortran.
The largest and highest-risk modules are:

| Module | Approximate lines | GPU relevance |
|---|---:|---|
| `JU_xJU_yJU_z6.f90` | 24,784 | Generated interior and boundary stencil kernels |
| `RHS_Interior.f90` | 3,480 | Dispatch, near-boundary loops, PML and SAT coupling |
| `Interface_Condition.f90` | 2,889 | Multi-block/fault interface physics |
| `grid.f90` | 2,740 | Geometry and metrics, mainly initialization |
| `material.f90` | 2,001 | Material and attenuation allocation/initialization |
| `moment_tensor.f90` | 1,333 | Source mapping and forcing |
| `metrics.f90` | 1,284 | Curvilinear metric construction |
| `seismogram.f90` | 962 | Receiver mapping and host output |
| `mpi3dcomm.f90` | 781 | Cartesian decomposition and six-face halo exchange |
| `input_preflight.f90` | 775 | Root parsing, validation, decomposition and broadcast |

There are approximately 307 explicit allocation sites. Most runtime state is
held in nested derived types with allocatable components.

No OpenACC, OpenMP target, CUDA Fortran, or GPU data directives currently exist.

### 2.2 Precision

- `common.f90` sets working precision `wp` to approximately IEEE float64.
- `mpi3dbasic.f90` uses `MPI_DOUBLE_PRECISION` for computation.
- Distributed output normally converts to float32 through `ps=4`.

GPU qualification must begin in float64. Mixed or float32 computation is a
separate future physics qualification and must not be introduced as a migration
shortcut.

### 2.3 Runtime execution order

`main.f90` initializes MPI, validates and broadcasts input, initializes the
domain, and calls `time_step_RK` for every timestep.

Every one of the five Kennedy-Carpenter stages performs:

```text
exchange_fields
    -> scale_rates(A_stage)
    -> set_rates
    -> exchange_fields_interface
    -> enforce_bound_iface_conditions
    -> optional stage-1 output
    -> update_fields(B_stage * dt)
```

This stage ordering is part of the reference algorithm. GPU migration must not
move halo exchange, source evaluation, SAT forcing, or output to a different RK
time without a separate numerical proof and regression test.

### 2.4 Primary state

For each locally owned block:

- `F%F`: velocity/stress state with nine components and ghost cells;
- `F%DF`: low-storage RK rate/residual with nine components and ghost cells;
- `G%x`, `metricx`, `metricy`, `metricz`, and `J`: grid and metric arrays;
- `M%M`: material fields;
- optional anelastic state and rate arrays;
- optional plastic state;
- six boundary objects;
- up to six compact face-local PML `Q` and `DQ` arrays.

The primary layout is `F(x,y,z,component)`. Because Fortran's first index is
contiguous, assigning the GPU vector dimension to `x` naturally supports
coalesced access for a fixed component. The layout should remain unchanged
during initial acceleration.

### 2.5 PML

`pml.f90` already allocates PML state only on ranks intersecting a global PML
face. Each active face owns nine `Q` fields and nine `DQ` rate fields. Edges
and corners are represented by multiple directional face objects.

The active RHS implements compact face-local CFS ADE-PML. This layout should be
preserved. It is better suited to distributed GPUs than a full-volume PML.

### 2.6 MPI decomposition and communication

`mpi3dcomm.f90` constructs a Cartesian MPI communicator with selectable 1-D,
2-D, 3-D, or manual process topology. Each local block has `nb` ghost cells.

At every RK stage:

- all nine physical fields are exchanged individually;
- each field makes six blocking `MPI_SendRecv` calls;
- MPI derived datatypes describe noncontiguous faces;
- a stage therefore performs up to 54 blocking block-halo calls per block;
- a separate blocking exchange copies multi-block interface fields into
  `Fopp` arrays.

The source contains a note to pack all fields together for more efficient
communication. That change is essential for performant GPU-aware MPI.

MPI derived datatypes built for host Fortran arrays must not be assumed to work
correctly or efficiently with OpenACC device pointers. Explicit contiguous
device send/receive buffers are the recommended distributed design.

### 2.7 GPU-hostile constructs requiring attention

- Allocatable `save` work arrays occur in point stencil routines. They are
  shared mutable state and cannot safely become per-thread GPU scratch.
- Some near-boundary routines allocate small work vectors and call point
  kernels from nested loops.
- Nested derived types require explicit device-data ownership; a shallow copy
  of the parent does not guarantee correct attachment of every allocatable
  component.
- Boundary, source, attenuation, PML, friction, and plastic paths contain many
  branches. Porting everything in one kernel would be difficult to verify and
  can cause warp divergence.
- CPU output routines assume host-visible field arrays.
- The current timing uses `cpu_time` on the master rank; it does not measure
  synchronized GPU wall time or the slowest MPI rank.

## 3. Backend decision

### Recommended first backend: OpenACC with NVIDIA HPC SDK

Use OpenACC directives for the first production GPU backend because:

- the numerical implementation remains Fortran;
- directives are ignored by the existing CPU compiler path;
- persistent device data and host/device updates can be introduced gradually;
- NVIDIA HPC SDK supports H100, CUDA-aware MPI, and OpenACC profiling;
- individual kernels can later be replaced by CUDA Fortran only when profiling
  justifies the additional maintenance.

### Alternatives

| Option | Advantage | Migration risk | Recommendation |
|---|---|---|---|
| OpenACC/NVHPC | Incremental, mature NVIDIA Fortran path | Compiler-specific tuning | Primary path |
| OpenMP target | More vendor-neutral | Fortran derived-type/offload maturity varies | Maintain design compatibility; evaluate later |
| CUDA Fortran | Maximum control | Large invasive rewrite and duplicated kernels | Use only for proven hotspots after OpenACC |
| C++/CUDA rewrite | Broad CUDA tooling | Highest physics and maintenance divergence | Do not use for initial migration |
| JAX rewrite | Productive array model | Separate solver, not migration of this code | Keep as independent implementation |

## 4. Target software architecture

Build both backends from the same source tree:

```text
physics, FD, RK, PML, source, boundary equations
                         |
             backend-neutral orchestration
                    /             \
             CPU/MPI path      OpenACC/MPI path
```

Suggested new modules:

```text
accelerator_runtime.f90
    backend selection, local-rank GPU binding, capability reporting

accelerator_data.f90
    enter/exit data, allocatable-component attachment, update policy

gpu_halo.f90
    face packing/unpacking, staged MPI and GPU-aware MPI transport

gpu_diagnostics.f90
    synchronization, timers, memory and kernel error checks
```

Suggested CMake options:

```text
WQL_ENABLE_GPU=OFF|ON             default OFF
WQL_GPU_MODEL=OPENACC             initial supported value
WQL_GPU_ARCH=cc90                 H100 default on Punakha
WQL_GPU_AWARE_MPI=OFF|AUTO|ON     default AUTO
WQL_ENABLE_GPU_DEBUG=OFF|ON
```

The CPU target must continue to compile with its existing compilers. A GPU
build should add NVIDIA flags similar to:

```text
-acc -gpu=cc90,lineinfo -Minfo=accel
```

Exact flags must be verified against the installed NVIDIA HPC SDK version.
Debug and sanitizer flags belong in a separate build type, not in production.

## 5. User-visible execution controls

Add accelerator controls with CPU-safe defaults:

```text
execution_backend = 'cpu'       ! cpu | openacc
gpu_device = -1                 ! -1 means derive from node-local MPI rank
gpu_aware_mpi = 'auto'          ! off | auto | on
gpu_overlap = .false.           ! disabled until synchronous path qualifies
```

During early development these may be environment variables to avoid changing
input parsing. Before production they should be validated configuration values
broadcast from rank zero and printed during preflight.

Unsupported combinations must fail before field allocation.

## 6. Mandatory test hierarchy

Every phase uses the following hierarchy:

1. **Compile test:** CPU and GPU targets build with warnings captured.
2. **Unit/kernel test:** a small deterministic array exercises one kernel.
3. **One-stage test:** compare all affected rate arrays after one RK stage.
4. **One-step test:** compare state and rate arrays after all five stages.
5. **Short simulation:** compare full fields, receivers, and energy histories.
6. **Existing regression:** run all applicable CTest fixtures.
7. **Decomposition test:** compare one rank against two or more ranks.
8. **Performance test:** measure only after correctness gates pass.

Use float64 comparison norms:

```text
L_inf absolute error
L_inf relative error
L2 relative error
maximum receiver phase/time shift
energy difference
PML reflection ratio
```

Declare tolerances before running a new backend. Begin with:

- exact comparison for initialization and pack/unpack;
- `rtol=1e-13`, `atol=1e-14` for isolated algebraic kernels where operation
  order is unchanged;
- `rtol=1e-11`, `atol=1e-13` for one complete float64 stage;
- a documented accumulated tolerance for full runs.

Relax tolerances only after identifying the floating-point operation-order
difference. Never replace a failed field comparison with only a visual plot.

## 7. Phase-by-phase implementation plan

### Phase 0 — freeze the MPI/CPU oracle

Tasks:

- Record the exact source commit and compiler/MPI versions.
- Build release and bounds-checked debug configurations.
- Run the complete current CTest suite.
- Archive stdout, receiver files, plane/fault output, final-state diagnostics,
  and return codes.
- Add small deterministic fixtures for:
  - traditional elastic, Cartesian, no PML;
  - compact PML;
  - upwind order 6;
  - upwind-DRP order 6;
  - curvilinear mesh;
  - Q4, Q8, and fQ8;
  - two-block locked interface;
  - friction and plasticity.
- Export full `F` and `DF` arrays after one stage and one timestep for small
  cases.
- Replace or supplement master `cpu_time` reporting with synchronized
  `MPI_Wtime`; report min/mean/max across ranks.

Gate:

- CPU debug and release results are archived and reproducible.
- Existing one-rank/two-rank Q decomposition tests pass.
- No GPU changes begin until the CPU oracle is stable.

### Phase 1 — create a dual-backend build without offloading

Tasks:

- Add the CMake options listed above.
- Add an `accelerator_runtime` module whose CPU implementation is a no-op.
- Build the complete source with NVFORTRAN but with accelerator execution
  disabled.
- Add startup reporting: backend, compiler, GPU count, MPI library, precision,
  and GPU-aware MPI mode.
- Map MPI node-local ranks using `MPI_Comm_split_type(MPI_COMM_TYPE_SHARED)`.
- Validate one rank per GPU; reject accidental oversubscription by default.

Gate:

- GNU/Intel CPU builds remain unchanged.
- NVFORTRAN CPU execution matches the CPU oracle.
- One-rank and multi-rank CPU CTests pass under the new build system.

### Phase 2 — eliminate unsafe kernel scratch and instrument memory

Tasks:

- Replace allocatable `save` vectors inside point routines with fixed-size
  automatic arrays, private scalars, or caller-provided workspace.
- Remove allocation/deallocation from timestep and grid-point loops.
- Confirm all work arrays have thread-private semantics.
- Inventory every persistent array by owner, shape, bytes, initialization
  location, mutation location, communication requirement, and output use.
- Add per-rank host and predicted device memory reporting.
- Add a preflight capacity check with explicit headroom.

Gate:

- Threaded CPU tests show no races.
- CPU results remain within the frozen baseline.
- No allocation occurs in the steady-state RK stage, verified by profiling or
  allocation instrumentation.

### Phase 3 — persistent device-data ownership

Tasks:

- Keep input parsing, mesh/material construction, and file initialization on
  the CPU.
- After `init_domain`, enter one persistent OpenACC data region for the complete
  simulation.
- Explicitly copy each required allocatable leaf array; do not depend on an
  implicit deep copy of `domain_type`.
- Mark immutable grid/material arrays as copy-in.
- Create state/rate/PML/attenuation arrays on device and initialize them once.
- Define explicit host update routines for diagnostics and output.
- Exit and detach data in reverse ownership order during shutdown.
- Add `present` assertions/directives inside offloaded routines so accidental
  hidden transfers fail during development.

Gate:

- A no-kernel smoke test enters and exits all device data without leaks.
- Device memory reported by the runtime agrees with the inventory within a
  documented overhead.
- No full-volume transfer occurs inside an RK timestep.
- CPU backend behavior remains unchanged.

### Phase 4 — offload low-risk RK vector kernels

Port first:

- `F%DF = A*F%DF`;
- `F%F = F%F + dt*F%DF`;
- PML `DQ` scaling and `Q` update;
- attenuation memory-variable scaling and update;
- simple finite-value reductions in a debug-only path.

Use explicit `gang`, `vector`, and `collapse` choices. Preserve `x` as the
contiguous vectorized index. Do not fuse all arrays initially; separate kernels
are easier to compare.

Gate:

- Kernel unit tests pass for asymmetric local shapes and ghost widths.
- One complete RK update with a synthetic rate matches the CPU.
- Profiler confirms kernels execute on GPU and no implicit array copies occur.

### Phase 5 — single-GPU traditional Cartesian elastic RHS

Scope is deliberately narrow:

```text
one MPI rank
one GPU
one block
Cartesian grid
homogeneous elastic
traditional order 6
no PML
no attenuation
no fault/plasticity
receivers only
```

Tasks:

- Port `JJU_x6_interior` as the principal full-volume kernel.
- Separate strict interior from physical-boundary closures.
- Keep coefficient arrays read-only and resident.
- Port `RHS_near_boundaries` only for the traditional operator.
- Port moment-source injection without copying the full state to host.
- Preserve `DF <- A*DF + RHS` low-storage semantics exactly.

Gate:

- Point stencil tests for constants, linear fields, and manufactured waves pass.
- One-stage `DF`, one-step `F`, and receiver histories match CPU tolerances.
- CPU and GPU use the identical `dt`, RK coefficients, source convention, and
  boundary indices.
- Compute Sanitizer reports no illegal access or race.
- Single-GPU steady-state timing excludes initialization, JIT is irrelevant,
  and output-disabled performance is reported separately.

### Phase 6 — physical boundaries, SAT, source, and compact PML

Tasks:

- Port boundary field preparation and SAT forcing.
- Keep boundary kernels separate by face to reduce branching.
- Port compact face-local CFS ADE-PML in the order:
  1. one face;
  2. opposing faces;
  3. one edge;
  4. one corner;
  5. all enabled faces.
- Port PML terminal boundary treatment.
- Verify that ranks not touching global PML allocate no device PML arrays.
- Add PML memory and time counters.

Gate:

- CPU/GPU PML `Q`, `DQ`, physical `F`, and `DF` agree after every RK stage in a
  small test.
- Normal P/S, oblique, grazing, edge, and corner reflection tests pass.
- Long-time energy shows no GPU-only growth.
- PML adds no host/device transfer inside the timestep.

### Phase 7 — single-GPU FD and geometry expansion

Port and qualify one independent axis at a time:

1. upwind order 2, then 4, then 6;
2. upwind-DRP order 3/4/5/6;
3. remaining currently supported orders only if required by production inputs;
4. curvilinear metrics and topography;
5. variable material fields.

The 24,784-line generated stencil module should not be manually edited in many
places without a generation or transformation strategy. Add either:

- a reproducible stencil generator that emits CPU and OpenACC loop variants;
  or
- small wrapper kernels around shared coefficient tables.

Gate:

- Each FD family has derivative polynomial tests and wave-propagation tests.
- Axis permutation tests pass.
- Cartesian and curvilinear CPU/GPU receiver traces meet declared tolerances.
- Performance is reported separately for traditional, upwind, and DRP.

### Phase 8 — attenuation, interfaces, faults, and plasticity

Port in separate subphases:

#### 8A: anelastic models

- Q4;
- Q8;
- fQ8 full layout;
- fQ8 coarse-grained layout;
- constant/frequency-Q variants still supported by inputs.

Use the existing one-rank/two-rank final-state regression diagnostics and add
full memory-variable comparisons.

#### 8B: two-block locked interface

- Port boundary copies, `Fopp`, interface traction/velocity calculations, SAT
  additions, and interface state updates.
- Begin with both blocks on one GPU.

#### 8C: friction and rupture

- Port slip-weakening first;
- then rate-and-state variants;
- verify rupture time, slip, slip rate, traction, and state variable histories.

#### 8D: plasticity

- Port the final-stage plastic update;
- verify yield activation masks and plastic strain histories.

Gate:

- Every subphase passes its own CPU/GPU physics regression before the next is
  enabled.
- Unsupported physics is rejected in GPU preflight rather than silently run on
  CPU with full-volume transfers.

### Phase 9 — production single-GPU I/O and diagnostics

Tasks:

- Keep MPI-IO and formatted station files on the host.
- Gather only requested receiver values to host at output steps.
- Pack plane/fault output on GPU into contiguous staging buffers.
- Use pinned host buffers and asynchronous transfer where supported.
- Synchronize only at required output and safety intervals.
- Add GPU wall time, kernel time, transfer time, output time, memory high-water
  mark, and effective grid-point updates/s.

Gate:

- Output files match the CPU format and metadata.
- Output-enabled and output-disabled timings quantify I/O cost.
- Station-only runs never copy the complete field to host.
- Interrupted output leaves detectable incomplete files.

### Phase 10 — distributed GPUs with staged host MPI

This is the first correctness-oriented distributed path.

Tasks:

- Use one MPI rank per GPU.
- Begin with a `2 x 1 x 1` Cartesian decomposition.
- Pack all nine fields for each face into one contiguous device buffer.
- Copy send buffers device-to-host.
- Exchange host buffers with nonblocking `MPI_Irecv`/`MPI_Isend`.
- Copy receive buffers host-to-device and unpack ghost cells.
- Preserve the existing blocking stage semantics initially by waiting before
  computing the RHS.
- Replace 54 per-component blocking calls with at most twelve nonblocking
  requests for six faces per block.

Gate:

- Pack/unpack tests are exact for asymmetric subdomains and every face.
- One-GPU and two-GPU results agree within declared decomposition tolerances.
- No artificial signal is measurable at an internal partition beyond the
  tolerance.
- Compact PML exists only on global exterior ranks.
- Existing one-rank/two-rank attenuation tests pass on GPUs.

### Phase 11 — CUDA-aware MPI

Tasks:

- Detect CUDA-aware MPI capability at startup; do not infer it from an
  environment variable alone.
- Pass contiguous device send/receive buffers through `host_data use_device`.
- Keep the staged host path as a selectable fallback.
- Test intra-node communication before inter-node communication.
- Verify rank-to-GPU binding and report PCIe/NVLink/NVSwitch locality.
- Fail when `gpu_aware_mpi='on'` is requested but unavailable.

Gate:

- GPU-direct and staged paths produce equivalent halo data and simulations.
- Profiling confirms no unintended host staging in GPU-direct mode.
- Two-, four-, and eight-GPU single-node cases pass.

### Phase 12 — communication/computation overlap

Tasks:

- Split each RHS into strict interior and halo-dependent boundary regions.
- Post receives, pack and post sends.
- Compute the strict interior while transfers progress.
- Wait, unpack, then compute partition-boundary regions and SAT/PML work.
- Use separate accelerator queues only after dependency tests are present.

Gate:

- Overlap off and on produce equivalent results.
- A communication timeline demonstrates real overlap.
- Overlap is retained only if it improves steady-state runtime.
- Deadlock, message-order, and device-queue stress tests pass repeatedly.

### Phase 13 — 2-D/3-D decomposition and multi-node execution

Tasks:

- Qualify `2Dxy`, `2Dxz`, `2Dyz`, then full 3-D decomposition.
- Preserve the existing decomposition-safety constraints for stencil widths.
- Map process topology to hardware topology to minimize inter-node faces.
- Keep compact PML on exterior ranks only.
- Add weighted decomposition later if PML/fault ranks are measured as slower.
- Qualify multi-block interfaces when opposite blocks reside on different GPUs
  and nodes.

Gate:

- All six halo directions pass at least one cross-node test.
- Strong and weak scaling report min/mean/max rank time and communication
  fraction.
- Multi-node restart and output are integrity checked.
- No rank exceeds its measured GPU-memory headroom.

### Phase 14 — production hardening

Tasks:

- Add scheduler templates for Punakha and other target systems.
- Add startup checks for driver, GPU architecture, GPU count, rank binding,
  CUDA-aware MPI, and free memory.
- Add per-rank crash diagnostics and collective error propagation.
- Add deterministic small GPU tests to CI where hardware is available.
- Archive performance baselines by compiler and GPU model.
- Document supported and rejected physics/backend combinations.

Gate:

- Reproducible clean build and run instructions exist.
- CPU fallback passes the original suite.
- Single- and distributed-GPU qualification reports are complete.
- Default execution remains CPU until explicitly approved for change.

## 8. Distributed halo design

### Buffer layout

Use one contiguous buffer per face:

```text
buffer(component, halo_depth, tangent_1, tangent_2)
```

Pack all nine elastic fields together. Maintain a documented component order
identical to `F(:,:,:,1:9)`.

Do not send PML `Q` across ordinary internal subdomain interfaces. Send only
physical fields needed by the FD stencil. Multi-block fault/interface data is a
separate communication path and must not share tags or buffers silently.

### Message lifecycle

```text
post Irecv for active neighbors
    -> pack active send faces on GPU
    -> post Isend
    -> optional strict-interior computation
    -> Waitall
    -> unpack receive faces on GPU
    -> compute halo-dependent region
```

Use distinct communicators or robust tag ranges for:

- block halos;
- multi-block interfaces;
- output;
- diagnostics.

### Local rank binding

Derive node-local rank with `MPI_Comm_split_type`, then bind:

```text
device_id = local_rank mod visible_gpu_count
```

Reject `local_rank >= visible_gpu_count` unless explicit GPU sharing is enabled.
GPU sharing should not be used for performance qualification.

## 9. Output and restart strategy

The current distributed MPI-IO remains host-oriented. Do not depend on
GPU-aware MPI-IO.

Initial policy:

- receiver values: small device-to-host copies at output steps;
- plane/fault output: device pack followed by host staging;
- full checkpoint: one shard per MPI rank plus a manifest;
- restart: initially require identical rank and decomposition topology;
- later add an offline repartitioner for a different GPU count.

The manifest must contain:

- global block sizes and bounds;
- rank and device topology;
- local physical and ghost bounds;
- field component order;
- PML face ownership and shapes;
- attenuation/fault/plastic state presence;
- RK stage, timestep, and physical time;
- precision and endianness;
- source commit and checkpoint schema version.

## 10. Qualification matrix

| Dimension | Required cases |
|---|---|
| Backend | CPU oracle, NVFORTRAN CPU, one GPU, staged multi-GPU, GPU-direct multi-GPU |
| Precision | float64 computation; float32 output |
| GPU count | 1, 2, 4, all GPUs in one DGX, then two nodes |
| Decomposition | 1Dx, 1Dy, 1Dz, 2D variants, 3D/manual |
| FD | traditional-6, upwind-2/4/6, upwind-DRP production orders |
| Geometry | Cartesian, curvilinear/topography |
| Boundary | no PML, each PML face, edges, corners, free surface |
| Response | elastic, Q4, Q8, fQ8 full/coarse |
| Blocks | one block, two locked blocks, fault interface |
| Nonlinearity | slip weakening, rate/state, plasticity |
| Source | nearest/smooth moment sources used by production inputs |
| Output | receivers, planes, faults, checkpoint/restart |
| Duration | one stage, one step, short wave run, long stability run |

## 11. Performance methodology

Report separately:

- initialization and device-data setup;
- first timestep;
- steady-state timestep;
- each RK-stage phase;
- halo packing, MPI, unpacking, and wait time;
- PML, attenuation, source, SAT, and plastic/fault costs;
- output and checkpoint cost;
- peak device and host memory;
- achieved HBM bandwidth where profiling supports it;
- grid-point stages/s and grid-point timesteps/s.

Use `MPI_Wtime` with an `MPI_MAX` reduction for the authoritative timestep
time. The slowest rank determines simulation throughput.

Scaling reports:

- single H100 versus one CPU rank and the production CPU node allocation;
- strong scaling at fixed global grid;
- weak scaling at fixed local grid;
- staged versus GPU-direct MPI;
- synchronous versus overlapped communication;
- PML versus no-PML rank imbalance.

Performance goals are diagnostic, not correctness gates. A suggested target is
at least 70% parallel efficiency when doubling GPUs within one DGX for a domain
large enough to saturate every GPU. Do not claim this target until measured.

## 12. Tooling and diagnostics

Use:

- compiler accelerator reports (`-Minfo=accel`);
- NVIDIA Nsight Systems for MPI/kernel timelines;
- NVIDIA Nsight Compute for memory throughput, occupancy, and register usage;
- Compute Sanitizer for memory and race checking;
- OpenACC runtime notifications/timing in debug runs;
- MPI implementation diagnostics for CUDA-aware capability;
- CTest labels such as `cpu`, `gpu-single`, `gpu-mpi-staged`,
  `gpu-mpi-direct`, and `gpu-long`.

Never use profiler output from a correctness-failing binary as an optimization
baseline.

## 13. Primary risks and mitigations

| Risk | Mitigation |
|---|---|
| CPU behavior changes | Same sources, CPU default, frozen baselines |
| Derived-type shallow copy | Explicit leaf-array data manager and presence checks |
| Saved scratch arrays race | Remove before offloading point kernels |
| Hidden host/device transfer | Persistent data region and profiler gate |
| 24k-line stencil divergence | Generator/shared coefficient strategy |
| MPI datatype fails on device | Explicit contiguous face buffers |
| Too many MPI messages | Pack all nine fields per face |
| GPU oversubscription | Node-local rank binding and preflight rejection |
| PML rank imbalance | Measure first; later weighted decomposition |
| Fault/interface path silently on CPU | Reject unqualified GPU physics |
| Output forces full-state copy | Device-side receiver/plane packing |
| Different floating-point order | Predeclared norms and stage-level comparison |
| GPU OOM | Per-rank memory inventory and headroom check |
| CUDA-aware MPI unavailable | Tested host-staged fallback |
| Overlap introduces race/deadlock | Synchronous reference and queue dependency tests |
| Multi-node topology is poor | Hardware-aware Cartesian mapping |

## 14. Recommended first milestone on Punakha

```text
compiler:          NVIDIA HPC SDK / nvfortran
hardware:          one H100 80 GB
MPI ranks:         1
working precision: float64
blocks:            1
geometry:          Cartesian
response:          elastic
FD:                traditional order 6
RK:                Kennedy-Carpenter 5-stage RK4
PML:               disabled initially, then compact face-local PML
output:            receiver histories only
```

After this passes, use:

```text
hardware:          two H100 GPUs in one DGX
MPI ranks:         2, one per GPU
decomposition:     2 x 1 x 1
communication:     host-staged packed halos, then GPU-direct
```

Do not start with all GPUs, PML, attenuation, curvilinear geometry, and fault
physics enabled together. That would make numerical and communication defects
indistinguishable.

## 15. Completion criteria

The migration is production-complete only when:

1. The original CPU build and regression suite still pass.
2. One-GPU traditional elastic results match the CPU oracle.
3. Compact PML, all production FD methods, and curvilinear geometry qualify.
4. Required attenuation and rupture/plasticity physics qualify independently.
5. One MPI rank is reliably bound to each GPU.
6. Host-staged and CUDA-aware halo paths both pass decomposition tests.
7. All six halo directions and multi-block interfaces qualify.
8. Output and restart are integrity checked.
9. No steady-state full-volume host/device transfers occur.
10. Peak memory and slowest-rank time are reported.
11. Single-node and multi-node scaling reports are archived.
12. Unsupported combinations fail during preflight.
13. CPU remains a selectable reference backend.
14. The source contains one authoritative set of physics equations rather than
    permanently diverged CPU and GPU copies.

## 16. Immediate implementation backlog

The first development pull requests should be small and independently
reviewable:

1. Add synchronized phase timing and CPU baseline export.
2. Add dual-backend CMake options and accelerator runtime reporting.
3. Add node-local MPI rank and GPU binding checks.
4. Remove saved/allocatable point-kernel scratch arrays.
5. Add persistent data ownership for one-block elastic state.
6. Offload RK scale/update kernels.
7. Offload traditional Cartesian interior RHS.
8. Add one-stage and one-step CPU/GPU field comparisons.
9. Port physical boundary and source kernels.
10. Port compact PML one face at a time.
11. Add packed host-staged two-GPU halos.
12. Add CUDA-aware MPI and only then communication overlap.

Each pull request must include its verification command, numerical comparison,
and performance observation. A speedup is not sufficient evidence of a correct
migration.

