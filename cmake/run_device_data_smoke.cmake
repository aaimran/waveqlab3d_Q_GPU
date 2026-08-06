execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env WQL3D_PHASE3_MEMORY_RECONCILE=1
          "${MPIEXEC}" -np 1 "${EXE}" "${INPUT}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "Phase 3 device-data smoke failed: ${error}")
endif()

foreach(required
    "Persistent OpenACC device data:"
    "presence decision:          PASS"
    "cleanup decision:           PASS")
  string(FIND "${output}" "${required}" location)
  if(location EQUAL -1)
    message(FATAL_ERROR "missing Phase 3 diagnostic '${required}':\n${output}")
  endif()
endforeach()

string(REGEX MATCH "predicted device per rank: *([0-9.]+) MiB" predicted "${output}")
set(predicted_value "${CMAKE_MATCH_1}")
string(REGEX MATCH "explicit payload: *([0-9.]+) MiB" explicit "${output}")
set(explicit_value "${CMAKE_MATCH_1}")
if(predicted_value STREQUAL "" OR explicit_value STREQUAL "")
  message(FATAL_ERROR "Phase 3 memory diagnostics are missing:\n${output}")
endif()
if(NOT predicted_value STREQUAL explicit_value)
  message(FATAL_ERROR
    "inventory/device traversal mismatch: predicted=${predicted_value}, explicit=${explicit_value}")
endif()

string(REGEX MATCH "mapped allocatable leaves: *([0-9]+)" leaves "${output}")
if(CMAKE_MATCH_1 STREQUAL "" OR CMAKE_MATCH_1 LESS 1)
  message(FATAL_ERROR "Phase 3 smoke did not map any allocatable leaves")
endif()
