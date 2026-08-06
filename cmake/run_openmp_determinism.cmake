foreach(threads 1 2 4)
  execute_process(
    COMMAND ${CMAKE_COMMAND} -E env
      OMP_NUM_THREADS=${threads} OMP_PROC_BIND=close OMP_PLACES=cores
      "${EXE}" "${INPUT}"
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE error)
  if(NOT result EQUAL 0)
    message(FATAL_ERROR "${threads}-thread OpenMP run failed: ${error}")
  endif()
  string(REGEX MATCH "Elastic final state: max\\|field\\|=[^\n]+" state "${output}")
  if(state STREQUAL "")
    message(FATAL_ERROR "${threads}-thread final-state diagnostic is missing")
  endif()
  if(threads EQUAL 1)
    set(reference "${state}")
  elseif(NOT state STREQUAL reference)
    message(FATAL_ERROR "OpenMP mismatch: 1 thread: ${reference}; ${threads} threads: ${state}")
  endif()
endforeach()
