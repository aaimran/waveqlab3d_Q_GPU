cmake_minimum_required(VERSION 3.5)
project (WaveQLab3D Fortran)
set(CMAKE_VERBOSE_MAKEFILE ON)

# This branch requires MPI for compiling
FIND_PACKAGE(MPI REQUIRED)
add_definitions(${MPI_Fortran_COMPILE_FLAGS})
include_directories(${MPI_Fortran_INCLUDE_PATH})
link_directories(${MPI_Fortran_LIBRARY_PATH})


# This branch requires HDF5
#FIND_PACKAGE(HDF5 COMPONENTS Fortran)
#add_definitions(${HDF5_DEFINITIONS})
#include_directories(${HDF5_INCLUDE_DIRS})

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(WQL3D_OPENACC_LITERAL ".false.")
set(WQL3D_CUDA_AWARE_MPI_LITERAL ".false.")
set(WQL3D_BACKEND_NAME "cpu")
set(WQL3D_ACCELERATOR_RUNTIME accelerator_runtime_cpu.f90)
set(WQL3D_DEVICE_DATA device_data_cpu.f90)
set(WQL3D_RK_VECTOR_KERNELS rk_vector_cpu.f90)
set(WQL3D_TRADITIONAL_CARTESIAN_RHS traditional_cartesian_rhs_cpu.f90)
set(WQL3D_TRADITIONAL_BOUNDARY traditional_boundary_cpu.f90)
set(WQL3D_TRADITIONAL_BOUNDARY_RHS traditional_boundary_rhs_cpu.f90)
set(WQL3D_RK_VECTOR_TEST_DATA ../tests/rk_vector_test_data_cpu.f90)
set(WQL3D_ALLOCATION_TRACKING allocation_tracking_disabled.f90)
if(WQL3D_ENABLE_OPENACC)
    set(WQL3D_OPENACC_LITERAL ".true.")
    set(WQL3D_BACKEND_NAME "openacc")
    set(WQL3D_ACCELERATOR_RUNTIME accelerator_runtime_openacc.f90)
    set(WQL3D_DEVICE_DATA device_data_openacc.f90)
    set(WQL3D_RK_VECTOR_KERNELS rk_vector_openacc.f90)
    set(WQL3D_TRADITIONAL_CARTESIAN_RHS traditional_cartesian_rhs_openacc.f90)
    set(WQL3D_TRADITIONAL_BOUNDARY traditional_boundary_openacc.f90)
    set(WQL3D_TRADITIONAL_BOUNDARY_RHS traditional_boundary_rhs_openacc.f90)
    set(WQL3D_RK_VECTOR_TEST_DATA ../tests/rk_vector_test_data_openacc.f90)
endif()

if(WQL3D_ENABLE_CUDA_AWARE_MPI)
    set(WQL3D_CUDA_AWARE_MPI_LITERAL ".true.")
endif()
if(WQL3D_ENABLE_ALLOCATION_TRACKING)
    set(WQL3D_ALLOCATION_TRACKING allocation_tracking_enabled.f90 allocation_tracker.c)
endif()
configure_file(accelerator_build_config.f90.in
    ${CMAKE_CURRENT_BINARY_DIR}/accelerator_build_config.f90 @ONLY)

# The fortran compiler flags depends on the compiler being used
get_filename_component (Fortran_COMPILER_NAME ${CMAKE_Fortran_COMPILER} NAME)

if (CMAKE_Fortran_COMPILER_ID STREQUAL "NVHPC")
    # NVIDIA HPC SDK (nvfortran). OpenACC flags are supplied by the GPU
    # migration project so the CPU oracle build remains accelerator-neutral.
    set (CMAKE_Fortran_FLAGS_RELEASE "-O3")
    set (CMAKE_Fortran_FLAGS_DEBUG   "-O0 -g -traceback -Mbounds")
elseif (Fortran_COMPILER_NAME MATCHES "gfortran.*")
    # gfortran
    set (CMAKE_Fortran_FLAGS_RELEASE "-fdefault-real-8 -fdefault-double-8 -O5 -Wuninitialized")
    set (CMAKE_Fortran_FLAGS_DEBUG   "-fdefault-real-8 -fdefault-double-8 -Og -g -Wall -Wextra -Wconversion -Wuninitialized -fbounds-check -fbacktrace -finit-real=nan -ffpe-trap=invalid,zero,overflow -fimplicit-none -fall-intrinsics -std=f2008ts")
elseif (Fortran_COMPILER_NAME MATCHES "ifort.*")
    # ifort
    set (CMAKE_Fortran_FLAGS_RELEASE "-m64 -xHost -r8 -i4 -std08 -g -O2 -heap-arrays")
    # Keep runtime bounds/interface/stack checks usable.  -ftrapuv together
    # with -fpe0 aborts before main while legacy derived types are constructed.
    set (CMAKE_Fortran_FLAGS_DEBUG   "-r8 -i4 -std08 -g -heap-arrays -check all,noarg_temp_created -warn all -traceback -fp-stack-check -fltconsistency")
else (Fortran_COMPILER_NAME MATCHES "ftn.*")
    # Cray fortran compiler
    set (CMAKE_Fortran_FLAGS_RELEASE "-O2 -Oipa0 -v -V")
    set (CMAKE_Fortran_FLAGS_DEBUG   "-O0 -g")
endif()

# This needs to be set for the source code to become visible in the debugger.
# It will need to be expanded when we start using Linux and other OSes.
if(APPLE)
    set(DEBUGGING_SYMBOLS YES)
    set(DEBUG_INFORMATION_FORMAT dwarf-with-dsym)
endif(APPLE)

# Setup the source files and the executable name for the project.
set(WQL3D_SRC
  ${CMAKE_CURRENT_BINARY_DIR}/accelerator_build_config.f90
  ${WQL3D_ACCELERATOR_RUNTIME}
  ${WQL3D_ALLOCATION_TRACKING}
  fault_output.f90
  iface.f90
  block.f90
  boundary.f90
  common.f90
  diagnostics.f90
  decomposition_safety.f90
  datatypes.f90
  persistent_memory.f90
  ${WQL3D_DEVICE_DATA}
  ${WQL3D_RK_VECTOR_KERNELS}
  ${WQL3D_TRADITIONAL_CARTESIAN_RHS}
  ${WQL3D_TRADITIONAL_BOUNDARY}
  ${WQL3D_TRADITIONAL_BOUNDARY_RHS}
  domain.f90
  metrics.f90
  elastic.f90
  plastic.f90
  fields.f90
  grid.f90
  main.f90
  withers_tables.f90
  anelastic_q4_model.f90
  anelastic_q8_model.f90
  anelastic_fq8_model.f90
  simulation_config.f90
  input_preflight.f90
  material.f90
  plastic_material.f90
  pml.f90
  mpi3dbasic.f90
  mpi3dcomm.f90
  mpi3dio.f90
  mpi3d_interface.f90
  time_step.f90
  JU_xJU_yJU_z6.f90
  RHS_Interior.f90
  mms.f90
  BoundaryConditions.f90
  CouplingForcing.f90
  Interface_Condition.f90
  initial_stress_condition.f90
  inter_material.f90
  fault_output.f90
  unit_normals.f90
  seismogram.f90
  slice_output.f90
  plane_output.f90
  #hdf5_output.f90
  parallel_write.f90
  moment_tensor.f90
  )

set (PRE_WQL3D_SRC
    common.f90
    diagnostics.f90
    datatypes.f90
    grid.f90
    preprocessor.f90
    metrics.f90
    mpi3dbasic.f90
    mpi3dcomm.f90
    mpi3dio.f90
    mpi3d_interface.f90
  )

add_executable (waveqlab3d ${WQL3D_SRC})
add_executable (pre_wql3d ${PRE_WQL3D_SRC})
set_target_properties(waveqlab3d PROPERTIES
  Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/waveqlab3d_modules)
set_target_properties(pre_wql3d PROPERTIES
  Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/pre_wql3d_modules)
target_include_directories(waveqlab3d PRIVATE
  ${CMAKE_CURRENT_BINARY_DIR}/waveqlab3d_modules)
target_include_directories(pre_wql3d PRIVATE
  ${CMAKE_CURRENT_BINARY_DIR}/pre_wql3d_modules)
target_link_libraries (waveqlab3d ${MPI_Fortran_LIBRARIES})
target_link_libraries (pre_wql3d ${MPI_Fortran_LIBRARIES})
#target_link_libraries (waveqlab3d ${HDF5_LIBRARIES})

################################################
# Enable testing using example files
###############################################

enable_testing()

add_executable(fq8_effective_response_test
  common.f90
  withers_tables.f90
  anelastic_fq8_model.f90
  ../tests/fq8_effective_response_test.f90)
set_target_properties(fq8_effective_response_test PROPERTIES
  Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/fq8_test_modules)
target_include_directories(fq8_effective_response_test PRIVATE
  ${CMAKE_CURRENT_BINARY_DIR}/fq8_test_modules)
add_test(NAME fq8_effective_response_unit
  COMMAND $<TARGET_FILE:fq8_effective_response_test>)

add_executable(rk_vector_kernel_test
  common.f90
  ${WQL3D_RK_VECTOR_KERNELS}
  ${WQL3D_RK_VECTOR_TEST_DATA}
  ../tests/rk_vector_kernel_test.f90)
set_target_properties(rk_vector_kernel_test PROPERTIES
  Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/rk_vector_test_modules)
target_include_directories(rk_vector_kernel_test PRIVATE
  ${CMAKE_CURRENT_BINARY_DIR}/rk_vector_test_modules)
add_test(NAME rk_vector_kernel_unit COMMAND $<TARGET_FILE:rk_vector_kernel_test>)

if(WQL3D_ENABLE_OPENACC)
  add_executable(openacc_runtime_probe ../tests/openacc_runtime_probe.f90)
  add_test(NAME openacc_runtime_probe COMMAND $<TARGET_FILE:openacc_runtime_probe>)
  add_test(NAME rk_vector_kernel_launch
    COMMAND ${CMAKE_COMMAND}
      -D EXE=$<TARGET_FILE:rk_vector_kernel_test>
      -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_rk_vector_launch.cmake)
endif()

# Intel MPI's mpirun wrapper supplies its runtime-library environment, while
# the sibling mpiexec binary on this cluster does not.
get_filename_component(MPIEXEC_DIRECTORY ${MPIEXEC_EXECUTABLE} DIRECTORY)
set(WQL3D_MPI_RUNNER ${MPIEXEC_DIRECTORY}/mpirun)

if(WQL3D_ENABLE_OPENACC)
  add_test(NAME phase3_device_data_smoke
    COMMAND ${CMAKE_COMMAND}
      -D MPIEXEC=${WQL3D_MPI_RUNNER}
      -D EXE=$<TARGET_FILE:waveqlab3d>
      -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_elastic_traditional_o6.in
      -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_device_data_smoke.cmake)
  add_test(NAME phase5_traditional_cartesian_rhs_launch
    COMMAND ${CMAKE_COMMAND}
      -D MPIEXEC=${WQL3D_MPI_RUNNER}
      -D EXE=$<TARGET_FILE:waveqlab3d>
      -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_elastic_traditional_o6.in
      -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_phase5_rhs_launch.cmake)
  add_test(NAME phase6_lx_boundary_launch
    COMMAND ${CMAKE_COMMAND}
      -D MPIEXEC=${WQL3D_MPI_RUNNER}
      -D EXE=$<TARGET_FILE:waveqlab3d>
      -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_elastic_traditional_o6_lx.in
      -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_phase6_lx_launch.cmake)
  add_test(NAME phase6_all_face_boundary_launches
    COMMAND ${CMAKE_COMMAND}
      -D MPIEXEC=${WQL3D_MPI_RUNNER}
      -D EXE=$<TARGET_FILE:waveqlab3d>
      -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_elastic_traditional_o6.in
      -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_phase6_all_faces.cmake)
  foreach(fallback_case IN ITEMS
      test_elastic_upwind_o6.in
      test_anelastic_Q8_dynamic.in)
    get_filename_component(fallback_name ${fallback_case} NAME_WE)
    add_test(NAME phase5_fallback_${fallback_name}
      COMMAND ${CMAKE_COMMAND}
        -D MPIEXEC=${WQL3D_MPI_RUNNER}
        -D EXE=$<TARGET_FILE:waveqlab3d>
        -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/${fallback_case}
        -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_phase5_fallback.cmake)
  endforeach()
endif()

if(WQL3D_ENABLE_OPENMP)
  add_test(NAME openmp_elastic_determinism
    COMMAND ${CMAKE_COMMAND}
      -D EXE=$<TARGET_FILE:waveqlab3d>
      -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_elastic_traditional_o6.in
      -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_openmp_determinism.cmake)
endif()

add_test(NAME elastic_plane_output_smoke
  COMMAND ${CMAKE_COMMAND}
    -D EXE=$<TARGET_FILE:waveqlab3d>
    -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_elastic_plane_o6.in
    -D TEST_DIR=${CMAKE_CURRENT_BINARY_DIR}/test/plane_output
    -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_plane_output_smoke.cmake)

if(WQL3D_ENABLE_OPENACC)
  add_test(NAME gpu_memory_capacity_sufficient
    COMMAND ${WQL3D_MPI_RUNNER} ${MPIEXEC_NUMPROC_FLAG} 1
      $<TARGET_FILE:waveqlab3d>
      ${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_elastic_traditional_o6.in)
  set_tests_properties(gpu_memory_capacity_sufficient PROPERTIES
    ENVIRONMENT "WQL3D_GPU_MEMORY_BYTES=8589934592")

  add_test(NAME gpu_memory_capacity_rejects_insufficient
    COMMAND ${CMAKE_COMMAND}
      -D MPIEXEC=${WQL3D_MPI_RUNNER}
      -D NPROCS=1
      -D EXE=$<TARGET_FILE:waveqlab3d>
      -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_elastic_traditional_o6.in
      -D EXPECTED_CODE=RUN-GPU-MEM-002
      -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_expected_preflight_failure.cmake)
  set_tests_properties(gpu_memory_capacity_rejects_insufficient PROPERTIES
    ENVIRONMENT "WQL3D_GPU_MEMORY_BYTES=1048576")
endif()


set (no_mpi_proc 4)

file(MAKE_DIRECTORY
  ${CMAKE_CURRENT_BINARY_DIR}/test/1/data
  ${CMAKE_CURRENT_BINARY_DIR}/test/2/data
  ${CMAKE_CURRENT_BINARY_DIR}/test/3/data
  ${CMAKE_CURRENT_BINARY_DIR}/test/4/data)
  
add_test(NAME mpi_test1
  COMMAND ${CMAKE_COMMAND} 
    -D in=test_rup_cart_fric.in
    -D prefix=test_rup_cart_fric
    -D t=1
    -D n=${no_mpi_proc}
    -D TEST_PROBLEMS_DIR=${CMAKE_CURRENT_SOURCE_DIR}/../test_problems
    -D RESULT_CHECKER=${CMAKE_CURRENT_SOURCE_DIR}/../python/read_binary.py
    -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_mpi_test.cmake)

add_test(NAME q8_dynamic_decomposition
  COMMAND ${CMAKE_COMMAND}
    -D MPIEXEC=${WQL3D_MPI_RUNNER}
    -D EXE=$<TARGET_FILE:waveqlab3d>
    -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_anelastic_Q8_dynamic.in
    -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_q8_dynamic_regression.cmake)

add_test(NAME q4_dynamic_decomposition
  COMMAND ${CMAKE_COMMAND}
    -D MPIEXEC=${WQL3D_MPI_RUNNER}
    -D EXE=$<TARGET_FILE:waveqlab3d>
    -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_anelastic_Q4_dynamic.in
    -D STATE_LABEL=Q4
    -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_q8_dynamic_regression.cmake)

foreach(elastic_fd traditional upwind upwind_drp)
  add_test(NAME elastic_${elastic_fd}_o6_decomposition
    COMMAND ${CMAKE_COMMAND}
      -D MPIEXEC=${WQL3D_MPI_RUNNER}
      -D EXE=$<TARGET_FILE:waveqlab3d>
      -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_elastic_${elastic_fd}_o6.in
      -D STATE_LABEL=Elastic
      -D REQUIRE_MEMORY=FALSE
      -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_q8_dynamic_regression.cmake)
endforeach()

add_test(NAME elastic_locked_interface_o6_decomposition
  COMMAND ${CMAKE_COMMAND}
    -D MPIEXEC=${WQL3D_MPI_RUNNER}
    -D EXE=$<TARGET_FILE:waveqlab3d>
    -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_elastic_locked_interface_o6.in
    -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_elastic_locked_interface_regression.cmake)

add_test(NAME q4_dynamic_pml_decomposition
  COMMAND ${CMAKE_COMMAND}
    -D MPIEXEC=${WQL3D_MPI_RUNNER}
    -D EXE=$<TARGET_FILE:waveqlab3d>
    -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_anelastic_Q4_dynamic_pml.in
    -D STATE_LABEL=Q4
    -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_q8_dynamic_regression.cmake)

add_test(NAME q4_asymmetric_three_ranks
  COMMAND ${WQL3D_MPI_RUNNER} ${MPIEXEC_NUMPROC_FLAG} 3
    $<TARGET_FILE:waveqlab3d>
    ${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_anelastic_Q4_asymmetric.in)

add_test(NAME q4_deprecated_alias
  COMMAND ${CMAKE_COMMAND}
    -D MPIEXEC=${WQL3D_MPI_RUNNER}
    -D EXE=$<TARGET_FILE:waveqlab3d>
    -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_anelastic_Q4_alias.in
    -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_q4_alias_regression.cmake)

foreach(q4_invalid_case legacy partial method nonpositive band)
  add_test(NAME q4_rejects_${q4_invalid_case}
    COMMAND ${CMAKE_COMMAND}
      -D MPIEXEC=${WQL3D_MPI_RUNNER}
      -D NPROCS=2
      -D EXE=$<TARGET_FILE:waveqlab3d>
      -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_anelastic_Q4_invalid_${q4_invalid_case}.in
      -D EXPECTED_CODE=CFG-Q4-001
      -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_expected_preflight_failure.cmake)
endforeach()

add_test(NAME q8_dynamic_pml_decomposition
  COMMAND ${CMAKE_COMMAND}
    -D MPIEXEC=${WQL3D_MPI_RUNNER}
    -D EXE=$<TARGET_FILE:waveqlab3d>
    -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_anelastic_Q8_dynamic_pml.in
    -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_q8_dynamic_regression.cmake)

add_test(NAME fq8_coarse_grain_2_dynamic_decomposition
  COMMAND ${CMAKE_COMMAND}
    -D MPIEXEC=${WQL3D_MPI_RUNNER}
    -D EXE=$<TARGET_FILE:waveqlab3d>
    -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_anelastic_fQ8_withers.in
    -D STATE_LABEL=fQ8
    -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_q8_dynamic_regression.cmake)

add_test(NAME fq8_coarse_grain_0_dynamic_decomposition
  COMMAND ${CMAKE_COMMAND}
    -D MPIEXEC=${WQL3D_MPI_RUNNER}
    -D EXE=$<TARGET_FILE:waveqlab3d>
    -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_anelastic_fQ8_full.in
    -D STATE_LABEL=fQ8
    -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_q8_dynamic_regression.cmake)

add_test(NAME fq8_rejects_full_withers
  COMMAND ${CMAKE_COMMAND}
    -D MPIEXEC=${WQL3D_MPI_RUNNER}
    -D NPROCS=2
    -D EXE=$<TARGET_FILE:waveqlab3d>
    -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_anelastic_fQ8_invalid_full_withers.in
    -D EXPECTED_CODE=CFG-FQ8-001
    -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_expected_preflight_failure.cmake)

add_test(NAME q8_asymmetric_three_ranks
  COMMAND ${WQL3D_MPI_RUNNER} ${MPIEXEC_NUMPROC_FLAG} 3
    $<TARGET_FILE:waveqlab3d>
    ${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_anelastic_Q8_asymmetric.in)

add_test(NAME decomposition_rejects_excessive_split
  COMMAND ${CMAKE_COMMAND}
    -D MPIEXEC=${WQL3D_MPI_RUNNER}
    -D NPROCS=4
    -D EXE=$<TARGET_FILE:waveqlab3d>
    -D INPUT=${CMAKE_CURRENT_SOURCE_DIR}/../inputfile/test_anelastic_Q8_current.in
    -D EXPECTED_CODE=CFG-DECOMP-101
    -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_expected_preflight_failure.cmake)

add_test(NAME mpi_test2
  COMMAND ${CMAKE_COMMAND} 
    -D in=test_rup_curv_fric.in
    -D prefix=test_rup_curv_fric
    -D t=2
    -D n=${no_mpi_proc}
    -D TEST_PROBLEMS_DIR=${CMAKE_CURRENT_SOURCE_DIR}/../test_problems
    -D RESULT_CHECKER=${CMAKE_CURRENT_SOURCE_DIR}/../python/read_binary.py
    -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_mpi_test.cmake)

add_test(NAME premesh_test1
  COMMAND ${CMAKE_COMMAND} 
    -D in=test_rup_cart_fric_premesh.in
    -D prefix=test_rup_cart_fric
    -D t=1
    -D n=${no_mpi_proc}
    -D TEST_PROBLEMS_DIR=${CMAKE_CURRENT_SOURCE_DIR}/../test_problems
    -D RESULT_CHECKER=${CMAKE_CURRENT_SOURCE_DIR}/../python/read_binary.py
    -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_test.cmake)

add_test(NAME premesh_test2
  COMMAND ${CMAKE_COMMAND} 
    -D in=test_rup_curv_fric_premesh.in
    -D prefix=test_rup_curv_fric
    -D t=2
    -D n=${no_mpi_proc}
    -D TEST_PROBLEMS_DIR=${CMAKE_CURRENT_SOURCE_DIR}/../test_problems
    -D RESULT_CHECKER=${CMAKE_CURRENT_SOURCE_DIR}/../python/read_binary.py
    -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_test.cmake)

add_test(NAME serial_test1
  COMMAND ${CMAKE_COMMAND} 
    -D in=test_rup_cart_fric.in
    -D prefix=test_rup_cart_fric
    -D t=1
    -D n=1
    -D TEST_PROBLEMS_DIR=${CMAKE_CURRENT_SOURCE_DIR}/../test_problems
    -D RESULT_CHECKER=${CMAKE_CURRENT_SOURCE_DIR}/../python/read_binary.py
    -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_mpi_test.cmake)

add_test(NAME serial_test2
  COMMAND ${CMAKE_COMMAND} 
    -D in=test_rup_curv_fric.in
    -D prefix=test_rup_curv_fric
    -D t=2
    -D n=1
    -D TEST_PROBLEMS_DIR=${CMAKE_CURRENT_SOURCE_DIR}/../test_problems
    -D RESULT_CHECKER=${CMAKE_CURRENT_SOURCE_DIR}/../python/read_binary.py
    -P ${CMAKE_CURRENT_SOURCE_DIR}/../cmake/run_mpi_test.cmake)

##############################################################
#
# Add a target to generate API documentation with Doxygen
#
##############################################################

find_package(Doxygen)
if(DOXYGEN_FOUND)
    configure_file(${CMAKE_CURRENT_SOURCE_DIR}/../conf/Doxyfile.in
        ${CMAKE_CURRENT_BINARY_DIR}/Doxyfile @ONLY)
    add_custom_target(docs
        ${DOXYGEN_EXECUTABLE} ${CMAKE_CURRENT_BINARY_DIR}/Doxyfile
        WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
        COMMENT "Generating API documentation with Doxygen" VERBATIM
        )
endif(DOXYGEN_FOUND)
