execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    WQL3D_GPU_MEMORY_BYTES=8589934592 NVCOMPILER_ACC_NOTIFY=1
    "${MPIEXEC}" -np 1 "${EXE}" "${INPUT}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error)
set(combined "${output}\n${error}")
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Phase 5 fallback run failed (${result}):\n${combined}")
endif()
if(combined MATCHES "function=cartesian_elastic_o6_interior_kernel")
  message(FATAL_ERROR "Out-of-scope case incorrectly launched the Phase 5 kernel:\n${combined}")
endif()
if(NOT output MATCHES "final state: max\\|field\\|=")
  message(FATAL_ERROR "Fallback final-state diagnostic is missing:\n${combined}")
endif()
