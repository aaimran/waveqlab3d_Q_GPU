# Development status

Last updated: 2026-08-06

## Current phase

Phases 0-3 are complete and qualified with GNU and NVHPC. Phase 4 low-risk RK
vector-kernel offload is next; no numerical kernel is offloaded yet.

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
- Seventeen point-stencil routines now use private fixed nine-component work
  arrays; 53 hot-path first-call allocations and their shared `save` state were
  removed reproducibly.
- All 158 `copyin`/`create` persistent-array declarations now have generated,
  explicit OpenACC leaf traversal with presence checks, exact byte accounting,
  reverse cleanup, and an explicit host-update API.

## Not implemented yet

- No numerical kernel is offloaded.
- No simulation array is persistent on device.
- CUDA-aware MPI has not been exercised; its option currently records intent.
- No GPU result is qualified for scientific use.

## Next gate

1. Offload the low-risk `DF` scaling and `F` update RK vector kernels using the
   existing persistent leaf ownership.
2. Add asymmetric-shape kernel tests and one synthetic complete RK update.
3. Preserve the CPU implementation and frozen numerical oracle.
4. Require `present` data and verify no implicit transfers with NVHPC runtime
   notifications/profiling.
5. Keep CUDA-aware MPI disabled.

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

OpenACC accelerator-runtime verification passed on Punakha on 2026-08-06:

- one global/local rank detected one visible H100 and selected GPU 0;
- backend, 64-bit precision, and CUDA-aware MPI-disabled intent were correct;
- Q8 completed five steps and reproduced `max|field|=1.8221E+02` and
  `max|memory|=1.4544E+01`;
- runtime cleanup and MPI finalization completed normally;
- test-only two-rank/one-H100 Q8 and Q4 decomposition checks passed in 7.82 s
  and 6.79 s respectively.

Default GPU oversubscription rejection passed on Punakha: two local MPI ranks
with one visible H100 were rejected before input/domain initialization with
dedicated error code 92.

Phase 2 point-scratch verification passed locally: the GNU debug build and the
selected fQ8/Q8/Q4 regression suite completed with no failures after all point
operator families were normalized. NVHPC and FD-family qualification remain
pending, and face-sized SAT/interface workspaces still require persistent
block/interface ownership.

Punakha NVHPC point-scratch qualification passed on 2026-08-06:

```text
cpu-release: fQ8 pass; Q8 pass (6.69 s); Q4 pass (5.91 s); total 12.61 s
gpu-h100:    fQ8 pass; Q8 pass (7.83 s); Q4 pass (6.58 s); total 14.42 s
```

Persistent ownership is now implemented for active block-boundary and
interface face workspaces. The local GNU debug build, fQ8/Q8/Q4 suite, and
46-step Cartesian and curvilinear serial interface smoke runs complete
normally. Persistent workspace accounting is active: the one-block 41-cubed
Q8 case uses 0.346 MiB and the serial two-block 21-cubed TPV5 case uses 0.323
MiB. Punakha NVHPC validation, a decomposition-compatible locked interface
oracle, and explicit upwind/upwind-DRP fixtures remain open.

Punakha NVHPC face-workspace qualification passed on 2026-08-06:

```text
cpu-release: fQ8 pass; Q8 pass (7.04 s); Q4 pass (5.91 s); total 12.96 s
gpu-h100:    fQ8 pass; Q8 pass (8.08 s); Q4 pass (6.80 s); total 14.88 s
```

All six checks passed. Persistent face-workspace ownership and accounting are
now qualified with GNU debug and NVHPC CPU/OpenACC builds. The next Phase 2
gate is explicit traditional, upwind-6, and upwind-DRP-6 numerical fixtures,
followed by a decomposition-compatible locked interface oracle.

Explicit order-6 elastic fixtures are now implemented for traditional,
upwind, and upwind-DRP operators. Each compares one-rank and two-rank global
final-state diagnostics and rejects zero or non-finite fields. The local GNU
debug suite passed all three fixtures plus fQ8/Q8/Q4 (6/6, 7.68 s). Punakha
NVHPC qualification of the new fixtures and a decomposition-compatible locked
interface oracle remain open.

Punakha NVHPC order-6 fixture qualification passed on 2026-08-06:

```text
cpu-release: traditional 5.59 s; upwind 5.50 s; upwind-DRP 6.03 s; 3/3 pass
gpu-h100:    traditional 6.44 s; upwind 6.27 s; upwind-DRP 6.77 s; 3/3 pass
```

The three-family point-stencil gate is closed for GNU and NVHPC builds. Since
numerical kernels are not offloaded yet, the H100 preset remains a compiler and
accelerator-runtime qualification. The remaining Phase 2 numerical gate is a
decomposition-compatible locked two-block interface oracle.

The locked interface oracle is now implemented with two 41-cubed blocks and a
nonzero source transmitted from block 1 into block 2. Serial shared ownership
and two-rank distributed ownership produced identical block maxima; the local
GNU debug test passed in 35.43 s.

Final Phase 2 Punakha qualification passed on 2026-08-06:

```text
cpu-release locked interface: pass, 40.40 s
gpu-h100 locked interface:    pass, 41.32 s
```

All Phase 2 numerical gates are closed. Before Phase 3 begins, Phase 2 still
requires a complete simulation-array ownership/byte inventory, predicted
device-memory and headroom preflight, plus steady-state allocation and threaded
CPU evidence. No numerical loop will be offloaded until these gates pass.

The structural persistent-array inventory is now reproducible through
`scripts/inventory_persistent_arrays.py`. It covers 178 allocatable components
and records ownership, rank/shape, role, device policy, initialization,
mutation, communication, and output use. Drift-check mode passes. Runtime byte
totals, predicted device capacity, and headroom enforcement remain next.

Exact runtime payload accounting is now implemented in
`src/persistent_memory.f90`. It traverses allocated grid, material/attenuation,
field/rate, PML, boundary/workspace, source/interface, and output leaves and
reports aggregate MPI and maximum-per-rank totals. A one-block 41-cubed elastic
case predicts 32.334 MiB per rank; Q8 predicts 109.961 MiB. Both decomposition
regressions pass. Explicit GPU capacity reserve and rejection remain next.

The IEEE signaling warnings printed after preflight occur during the
intentional Fortran `STOP` after `MPI_Finalize`; no timestep was executed.

Standalone-tree verification on 2026-08-06:

- configured and built using only `waveqlab3d_Q_GPU/src`;
- built `waveqlab3d`, `pre_wql3d`, and the fQ8 unit executable;
- passed `fq8_effective_response_unit`;
- passed one-rank preflight using the local `inputfile/test_moment_tensor.in`;
- confirmed the original `waveqlab3d_Q/src/CMakeLists.txt` has no migration
  diff.

GPU capacity/headroom enforcement is now implemented pending H100
qualification. OpenACC runs require an explicit `WQL3D_GPU_MEMORY_BYTES`
capacity, reserve 1 GiB plus 10% by default, and reject missing, malformed, or
insufficient capacity before the first RK step with dedicated diagnostics.
CPU runs retain payload reporting but skip enforcement. Deterministic OpenACC
CTest fixtures inject sufficient and insufficient capacities. The login-node
GNU debug build and selected fQ8/Q8/Q4/traditional/upwind/upwind-DRP suite
passed 6/6 while `WQL3D_GPU_MEMORY_BYTES=1` confirmed that CPU execution is not
rejected. NVHPC compilation and H100 pass/fail qualification are next.

Punakha H100 capacity qualification passed on 2026-08-06. NVHPC 26.5 built
the OpenACC backend, and deterministic synthetic-capacity tests passed for
both an 8 GiB acceptance case and a 1 MiB rejection case. The selected
fQ8/Q8/Q4/traditional/upwind/upwind-DRP suite passed 6/6 in 34.23 s. With the
physical H100 capacity configured as 81559 MiB, the Q8 fixture reported:

```text
predicted persistent payload:    109.961 MiB
fixed reserve:                  1024.000 MiB
fractional reserve:             8155.900 MiB (10%)
usable capacity:               72379.100 MiB
remaining headroom:            72269.139 MiB
decision: PASS
```

The Q8 final diagnostics remained `max|field|=1.8221E+02` and
`max|memory|=1.4544E+01`. The GPU capacity/headroom gate is closed. Remaining
Phase 2 gates are steady-state allocation evidence and threaded CPU
race-safety evidence.

The remaining Phase 2 allocation and threaded gates are implemented and have
passed login-node GNU qualification. The transitive source audit covers 131
procedures reachable from `time_step_RK`. A linker-level allocation tracker
then found and drove removal of hidden heap temporaries in near-boundary point
scratch, all six physical-boundary result functions, noncontiguous interface
face copies, and plane-output gathering. The allocation-audit build reports
zero timestep allocation calls for Q8, Q4, all three order-6 elastic families,
plane output, and the serial/two-rank locked-interface oracle.

The optional OpenMP build parallelizes the six independent physical-boundary
face loops with explicit private point state. Its 1/2/4-thread determinism
fixture reproduces `max|field|=1.6623E+02`, and the selected threaded
fQ8/Q8/Q4/traditional/upwind/upwind-DRP plus plane-output suite passed 8/8 in
64.94 s with four threads. Separate per-target Fortran module directories also
removed a parallel-build race between `waveqlab3d` and `pre_wql3d`.

Final Punakha qualification of commit `cee9e79` passed on 2026-08-06. A fresh
NVHPC 26.5 `gpu-h100` build passed the fQ8 unit, plane-output smoke, both GPU
capacity fixtures, Q8/Q4, and all three order-6 families (9/9, 41.23 s); the
locked-interface oracle passed separately in 41.21 s. The NVHPC allocation-
audit build passed the unit plus plane, Q8, Q4, traditional, upwind,
upwind-DRP, and locked-interface tests (8/8, 1393.91 s). The locked-interface
debug allocation run accounted for 1141.03 s and reported zero timestep heap
calls. Phase 2 is therefore closed.

Phase 3 persistent device-data ownership completed on Punakha on 2026-08-06.
Generated traversal covers all 158 device-policy declarations without mapping
`domain_type`; the CPU backend remains a no-op. The strict H100 smoke mapped 96
allocated leaves, matched the 32.334 MiB inventory exactly, measured 42.000 MiB
of device use (9.666 MiB runtime/allocator overhead), exercised explicit host
synchronization, and removed every present-table entry during reverse cleanup.
NVHPC notification output showed all 97 uploads before timestepping, no RK
transfers, and zero kernel launches. Focused H100 coverage passed 11/11 in
105.16 s, CPU oracle coverage passed 7/7 in 30.59 s, and allocation-tracked
plane/Q8 passed 2/2 in 69.57 s. Phase 3 is closed; see
`PHASE3_DEVICE_DATA_OWNERSHIP.md`.
