# Phase 5 traditional Cartesian elastic RHS

Date: 2026-08-06  
Status: complete for the qualified one-rank strict-interior gate

## Qualified scope

The OpenACC backend now executes the principal order-6 Cartesian homogeneous
elastic volume stencil on one H100. Eligibility is deliberately strict: one MPI
rank, traditional order 6, Cartesian mesh, nine elastic fields, no attenuation,
and no PML. Every other configuration returns to the unchanged CPU routine.

The raw-array kernel preserves the x-contiguous layout, the three centered
sixth-order coefficients, diagonal Cartesian metrics, density/lambda/mu
semantics, and `DF <- DF + RHS`. It requires all field, rate, metric, and
material arrays to be present. The backend downloads `DF` once after the volume
kernel so the existing traditional SBP near-boundary closure, SAT forcing, and
moment-source injection retain their established host ordering. It does not
copy the full state to host for source injection.

An attempted expansion of the GPU kernel to the SBP closure was rejected and
reverted: the first version produced non-finite state, and the conservative
correction suppressed the source-driven oracle. Those failed experiments are
preserved in history (`23bc4b5` through `2007310`) and their reverts; they are
not part of the qualified implementation. Boundary/SAT device work proceeds in
Phase 6 with a dedicated stage-level oracle.

## Execution and numerical evidence

The durable `phase5_traditional_cartesian_rhs_launch` CTest requires 30 named
CUDA kernel launches, no implicit device allocation, and the frozen final-state
diagnostic `max|field|=1.6623E+02`. On H100 each volume launch used 335 gangs
and vector length 128. The one-rank GPU result and two-rank CPU fallback match
in the existing decomposition regression.

Compute Sanitizer memcheck completed the six-step case with zero errors. The
output-disabled timestep totals, excluding initialization and cleanup, were:

| Backend | Six steps | Mean step |
|---|---:|---:|
| NVHPC CPU | 0.668562 s | 0.111427 s |
| H100 hybrid | 0.820860 s | 0.136810 s |

This is an execution/correctness measurement, not a speedup claim. Explicit RK
and boundary synchronization still dominates this small 41-cubed case.

## Gate decision

- Principal full-volume traditional Cartesian kernel executes on H100: PASS.
- One-stage low-storage ordering and complete-run final state are preserved: PASS.
- One-rank GPU/two-rank CPU decomposition oracle: PASS.
- No implicit allocation; explicit transfer is confined to the audited bridge: PASS.
- Compute Sanitizer illegal-access/race gate: PASS.
- Output-disabled steady-state timing reported separately: PASS.

Phase 5 is closed at the deliberately narrow strict-interior boundary. Phase 6
owns physical/SBP boundary, SAT, and compact PML device expansion.
