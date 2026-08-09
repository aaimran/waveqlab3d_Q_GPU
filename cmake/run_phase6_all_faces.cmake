execute_process(
  COMMAND ${MPIEXEC} -n 1 ${CMAKE_COMMAND} -E env
    WQL3D_PHASE6_DIAGNOSTICS=1 NVCOMPILER_ACC_NOTIFY=1 ${EXE} ${INPUT}
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
set(combined "${output}\n${error}")
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Phase 6 all-face run failed (${result}):\n${combined}")
endif()
string(REGEX MATCHALL "function=face_boundary_kernel" launches "${combined}")
list(LENGTH launches count)
if(NOT count EQUAL 180)
  message(FATAL_ERROR "Expected 180 Phase 6 face launches, found ${count}:\n${combined}")
endif()
string(REGEX MATCH "Elastic final state: max\\|field\\|=[ ]+1.6623128367649574E\\+02" final_state "${combined}")
if(NOT final_state)
  message(FATAL_ERROR "Phase 6 all-face final-state oracle is missing:\n${combined}")
endif()
