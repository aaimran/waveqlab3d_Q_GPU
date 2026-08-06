cmake_minimum_required(VERSION 3.24)
project(WaveQLab3D_GPU LANGUAGES Fortran)

include(CTest)

option(WQL3D_ENABLE_OPENACC "Compile WaveQLab3D with OpenACC" OFF)
option(WQL3D_ENABLE_CUDA_AWARE_MPI "Permit MPI device-buffer communication" OFF)
set(WQL3D_GPU_ARCH "cc90" CACHE STRING "NVHPC GPU architecture")
if(WQL3D_ENABLE_CUDA_AWARE_MPI AND NOT WQL3D_ENABLE_OPENACC)
  message(FATAL_ERROR "CUDA-aware MPI requires WQL3D_ENABLE_OPENACC=ON")
endif()

# The migration repository is standalone. Numerical CPU and accelerator paths
# are built from the same locally versioned sources.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/src"
                 "${CMAKE_CURRENT_BINARY_DIR}/solver")

foreach(target waveqlab3d pre_wql3d)
  if(TARGET "${target}")
    target_compile_definitions("${target}" PRIVATE
      WQL3D_GPU_MIGRATION_BUILD=1
      WQL3D_OPENACC_ENABLED=$<BOOL:${WQL3D_ENABLE_OPENACC}>
      WQL3D_CUDA_AWARE_MPI_ENABLED=$<BOOL:${WQL3D_ENABLE_CUDA_AWARE_MPI}>)
    if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
      # Generated stencil expressions legitimately exceed 132 columns.
      target_compile_options("${target}" PRIVATE -ffree-line-length-none)
    endif()
  endif()
endforeach()

if(WQL3D_ENABLE_OPENACC)
  if(NOT CMAKE_Fortran_COMPILER_ID STREQUAL "NVHPC")
    message(FATAL_ERROR
      "OpenACC requires NVHPC/nvfortran; detected ${CMAKE_Fortran_COMPILER_ID}")
  endif()
  foreach(target waveqlab3d pre_wql3d)
    if(TARGET "${target}")
      target_compile_options("${target}" PRIVATE
        $<$<COMPILE_LANGUAGE:Fortran>:-acc=gpu;-gpu=${WQL3D_GPU_ARCH},lineinfo>)
      target_link_options("${target}" PRIVATE
        -acc=gpu "-gpu=${WQL3D_GPU_ARCH},lineinfo")
    endif()
  endforeach()
endif()

message(STATUS "WaveQLab3D migration configuration")
message(STATUS "  Solver source:     ${CMAKE_CURRENT_SOURCE_DIR}/src")
message(STATUS "  OpenACC:           ${WQL3D_ENABLE_OPENACC}")
message(STATUS "  CUDA-aware MPI:    ${WQL3D_ENABLE_CUDA_AWARE_MPI}")
if(WQL3D_ENABLE_OPENACC)
  message(STATUS "  NVIDIA GPU arch:   ${WQL3D_GPU_ARCH}")
endif()
