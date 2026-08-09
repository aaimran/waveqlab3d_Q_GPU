execute_process(
  COMMAND ${CMAKE_COMMAND} -E env
    WQL3D_GPU_MEMORY_BYTES=85899345920
    WQL3D_PHASE6_DIAGNOSTICS=1
    NVCOMPILER_ACC_NOTIFY=1
    ${EXE} ${INPUT}
  RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error)
set(combined "${output}\n${error}")
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Phase 6 all-face PML run failed (${result}):\n${combined}")
endif()

foreach(kernel_count IN ITEMS
    "boundary_rhs_kernel;15"
    "face_boundary_kernel;90"
    "pml_face_kernel;90"
    "pml_sat_kernel;90")
  list(GET kernel_count 0 kernel)
  list(GET kernel_count 1 expected)
  string(REGEX MATCHALL "${kernel}" launches "${combined}")
  list(LENGTH launches count)
  if(NOT count EQUAL expected)
    message(FATAL_ERROR
      "Expected ${expected} ${kernel} launches, found ${count}:\n${combined}")
  endif()
endforeach()

string(REGEX MATCH
  "Elastic final state: max\\|field\\|=[ ]+2.1222703312170271E\\+01"
  physical_state "${combined}")
if(NOT physical_state)
  message(FATAL_ERROR "Phase 6 PML physical-state oracle is missing:\n${combined}")
endif()
string(REGEX MATCH
  "PML final state: max\\|Q\\|=[ ]+3.8949145546177959E-03, max\\|DQ\\|=[ ]+3.5670986502432694E-01"
  pml_state "${combined}")
if(NOT pml_state)
  message(FATAL_ERROR "Phase 6 PML Q/DQ oracle is missing:\n${combined}")
endif()
