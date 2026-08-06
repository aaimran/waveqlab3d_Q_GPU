if(NOT DEFINED STATE_LABEL)
  set(STATE_LABEL Q8)
endif()

# Tiny decomposition regressions may run inside an interactive allocation that
# exposes only one scheduler slot. Allow an explicit test-only override without
# changing production MPI launch behavior.
set(mpi_test_args)
if("$ENV{WQL3D_TEST_MPI_OVERSUBSCRIBE}" MATCHES "^(1|true|TRUE|yes|YES)$")
  list(APPEND mpi_test_args --map-by :OVERSUBSCRIBE)
endif()

execute_process(
  COMMAND "${MPIEXEC}" ${mpi_test_args} -np 1 "${EXE}" "${INPUT}"
  RESULT_VARIABLE result1
  OUTPUT_VARIABLE output1
  ERROR_VARIABLE error1)
if(NOT result1 EQUAL 0)
  message(FATAL_ERROR "one-rank ${STATE_LABEL} dynamic run failed: ${error1}")
endif()

execute_process(
  COMMAND "${MPIEXEC}" ${mpi_test_args} -np 2 "${EXE}" "${INPUT}"
  RESULT_VARIABLE result2
  OUTPUT_VARIABLE output2
  ERROR_VARIABLE error2)
if(NOT result2 EQUAL 0)
  message(FATAL_ERROR "two-rank ${STATE_LABEL} dynamic run failed: ${error2}")
endif()

string(REGEX MATCH "${STATE_LABEL} final state: max\\|field\\|=[^\n]+" state1 "${output1}")
string(REGEX MATCH "${STATE_LABEL} final state: max\\|field\\|=[^\n]+" state2 "${output2}")
if(state1 STREQUAL "" OR state2 STREQUAL "")
  message(FATAL_ERROR "${STATE_LABEL} final-state diagnostic is missing")
endif()
if(NOT state1 STREQUAL state2)
  message(FATAL_ERROR "decomposition mismatch:\n1 rank: ${state1}\n2 ranks: ${state2}")
endif()
if(state1 MATCHES "max\\|field\\|= *0\\.0+E\\+00")
  message(FATAL_ERROR "${STATE_LABEL} dynamic fixture did not produce a nonzero field")
endif()
if(state1 MATCHES "max\\|memory\\|= *0\\.0+E\\+00")
  message(FATAL_ERROR "${STATE_LABEL} dynamic fixture did not evolve memory variables")
endif()
