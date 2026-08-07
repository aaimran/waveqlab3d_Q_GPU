execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env
    WQL3D_GPU_MEMORY_BYTES=8589934592 NVCOMPILER_ACC_NOTIFY=3
    "${MPIEXEC}" -np 1 "${EXE}" "${INPUT}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error)
set(combined "${output}\n${error}")
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Phase 5 H100 run failed (${result}):\n${combined}")
endif()
string(REGEX MATCHALL "launch CUDA kernel[^\n]*function=cartesian_elastic_o6_interior_kernel" launches "${combined}")
list(LENGTH launches count)
if(NOT count EQUAL 30)
  message(FATAL_ERROR "Expected 30 Phase 5 RHS launches, found ${count}:\n${combined}")
endif()
string(REGEX MATCHALL "launch CUDA kernel[^\n]*function=cartesian_elastic_o6_interior_kernel[^\n]*num_gangs=191[^\n]*vector_length=128" geometry "${combined}")
list(LENGTH geometry geometry_count)
if(NOT geometry_count EQUAL 30)
  message(FATAL_ERROR "Expected corrected 29^3 interior launch geometry 30 times, found ${geometry_count}:\n${combined}")
endif()
if(combined MATCHES "implicit|create CUDA data")
  message(FATAL_ERROR "Unexpected implicit device allocation:\n${combined}")
endif()
if(NOT output MATCHES "Elastic final state: max\\|field\\|=")
  message(FATAL_ERROR "Phase 5 final-state oracle is missing:\n${combined}")
endif()
if(output MATCHES "Elastic final state: max\\|field\\|= *0\\.0+E\\+00")
  message(FATAL_ERROR "Phase 5 final state is unexpectedly zero:\n${combined}")
endif()
