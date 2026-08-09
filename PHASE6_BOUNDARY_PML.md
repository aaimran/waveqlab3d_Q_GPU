# Phase 6 boundary, SAT, source, and compact PML

## Implemented scope

The guarded single-rank traditional order-6 Cartesian elastic backend now
offloads the exact SBP near-boundary closure, six independent physical-face
characteristic/SAT kernels, six compact CFS ADE-PML face kernels, and terminal
PML SAT forcing. Edges and corners are the sum of their participating face
terms, matching the CPU formulation. Unsupported physics, decomposition,
operators, orders, and malformed storage retain the CPU fallback.

PML `Q` and `DQ` use resident RK scale/update entry points. PML RHS and terminal
SAT routines issue no host/device updates inside the timestep. The complete
resident domain state is copied back once after the timestep loop for shutdown
diagnostics. The point moment source remains on the established host fallback;
the general physical field/rate path therefore still has explicit staging.

## Qualification

The compact 21-cubed, six-face PML point-source fixture advances three
timesteps (15 RK stages). Its H100 execution gate requires 15 SBP launches and
90 launches each of the physical-face, compact-PML-face, and terminal-PML-SAT
kernels. Measured final states are:

```text
CPU  F=2.1222703312170282E+01  Q=3.8949144527974378E-03  DQ=3.5670984233027198E-01
H100 F=2.1222703312170271E+01  Q=3.8949145546177959E-03  DQ=3.5670986502432694E-01
```

The Phase 5/6 H100 suite passes 6/6. Singleton Compute Sanitizer memcheck
reports zero errors and racecheck reports zero hazards, errors, or warnings.
The CPU implementation remains the numerical fallback and oracle.

## Qualification boundary

This closes the Phase 6 implementation milestone for the supported
single-rank traditional Cartesian elastic path. It does not qualify arbitrary
multi-rank, alternate-FD, attenuation, curvilinear, fault, or production-scale
cases; those are assigned to later migration phases. Dedicated quantitative
reflection-coefficient and long-duration energy studies remain scientific
validation work and are not represented by the compact execution regression.
