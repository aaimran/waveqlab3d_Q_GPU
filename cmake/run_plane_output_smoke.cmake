file(REMOVE_RECURSE "${TEST_DIR}")
file(MAKE_DIRECTORY "${TEST_DIR}/data")
execute_process(
  WORKING_DIRECTORY "${TEST_DIR}"
  COMMAND "${EXE}" "${INPUT}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "plane-output run failed: ${error}")
endif()
set(plane "${TEST_DIR}/data/test_elastic_plane_o6_mid_block1.plane")
if(NOT EXISTS "${plane}")
  message(FATAL_ERROR "plane-output file was not created: ${plane}")
endif()
file(SIZE "${plane}" plane_size)
if(plane_size LESS 100)
  message(FATAL_ERROR "plane-output file is unexpectedly small: ${plane_size} bytes")
endif()
