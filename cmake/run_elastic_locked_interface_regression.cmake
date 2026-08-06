set(mpi_test_args)
if("$ENV{WQL3D_TEST_MPI_OVERSUBSCRIBE}" MATCHES "^(1|true|TRUE|yes|YES)$")
  list(APPEND mpi_test_args --map-by :OVERSUBSCRIBE)
endif()

foreach(rank_count 1 2)
  execute_process(
    COMMAND "${MPIEXEC}" ${mpi_test_args} -np ${rank_count} "${EXE}" "${INPUT}"
    RESULT_VARIABLE result${rank_count}
    OUTPUT_VARIABLE output${rank_count}
    ERROR_VARIABLE error${rank_count})
  if(NOT result${rank_count} EQUAL 0)
    message(FATAL_ERROR
      "${rank_count}-rank locked-interface run failed: ${error${rank_count}}")
  endif()
endforeach()

string(REGEX MATCH "Elastic block maxima: block1=[^\n]+" state1 "${output1}")
string(REGEX MATCH "Elastic block maxima: block1=[^\n]+" state2 "${output2}")
if(state1 STREQUAL "" OR state2 STREQUAL "")
  message(FATAL_ERROR "locked-interface block diagnostic is missing")
endif()
if(NOT state1 STREQUAL state2)
  message(FATAL_ERROR
    "locked-interface decomposition mismatch:\n1 rank: ${state1}\n2 ranks: ${state2}")
endif()
if(state1 MATCHES "block1= *0\\.0+E\\+00" OR
   state1 MATCHES "block2= *0\\.0+E\\+00")
  message(FATAL_ERROR "locked-interface fixture did not excite both blocks: ${state1}")
endif()

