execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env NVCOMPILER_ACC_NOTIFY=3 "${EXE}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE error)

set(combined "${output}\n${error}")
if(NOT result EQUAL 0)
  message(FATAL_ERROR "RK vector launch test failed (${result}):\n${combined}")
endif()

foreach(kernel scale_rate_kernel update_state_kernel)
  string(REGEX MATCHALL "launch CUDA kernel[^\n]*function=${kernel}" launches "${combined}")
  list(LENGTH launches count)
  if(NOT count EQUAL 1)
    message(FATAL_ERROR "Expected one ${kernel} launch, found ${count}:\n${combined}")
  endif()
endforeach()

if(combined MATCHES "implicit|create CUDA data")
  message(FATAL_ERROR "Unexpected implicit device allocation:\n${combined}")
endif()

if(NOT output MATCHES "rate= *0.0000E\\+00, state= *0.0000E\\+00")
  message(FATAL_ERROR "RK vector numerical oracle did not report zero error:\n${combined}")
endif()
