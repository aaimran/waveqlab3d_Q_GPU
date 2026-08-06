if(NOT DEFINED TEST_PROBLEMS_DIR)
  set(TEST_PROBLEMS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../test_problems)
endif()
if(NOT DEFINED RESULT_CHECKER)
  set(RESULT_CHECKER ${CMAKE_CURRENT_BINARY_DIR}/../python/read_binary.py)
endif()
set(dir ${CMAKE_CURRENT_BINARY_DIR}/test/${t})
file(MAKE_DIRECTORY
  ${dir}/data
  ${dir}/seismogram/block1/data
  ${dir}/seismogram/block2/data)
execute_process(
  WORKING_DIRECTORY ${dir}
  COMMAND ${CMAKE_COMMAND} -E copy ${TEST_PROBLEMS_DIR}/${in} ${in}
  COMMAND ${CMAKE_COMMAND} -E copy_directory ${TEST_PROBLEMS_DIR}/truth/${t} truth
  COMMAND mpirun -n ${n} ${CMAKE_CURRENT_BINARY_DIR}/waveqlab3d ${in})
set(results 0)
execute_process(
  COMMAND ${RESULT_CHECKER} ${dir} ${prefix}
  RESULT_VARIABLE test_fail)
math(EXPR results "${results} + ${test_fail}")
if (results)
  message( SEND_ERROR "waveqlab3d output for ${in} does not match true solution." )
endif (results)
