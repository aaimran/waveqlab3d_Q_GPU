cmake_minimum_required(VERSION 3.24)
project(WaveQLab3D_GPU LANGUAGES Fortran)

include(CTest)

option(WQL3D_ENABLE_OPENACC "Compile WaveQLab3D with OpenACC" OFF)
option(WQL3D_ENABLE_CUDA_AWARE_MPI "Permit MPI device-buffer communication" OFF)
set(WQL3D_GPU_ARCH "cc90" CACHE STRING "NVHPC GPU architecture")
set(WQL3D_CPU_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../waveqlab3d_Q"
    CACHE PATH "Immutable MPI/CPU reference source tree")

if(NOT EXISTS "${WQL3D_CPU_SOURCE_DIR}/src/CMakeLists.txt")
  message(FATAL_ERROR "Invalid CPU oracle tree: ${WQL3D_CPU_SOURCE_DIR}")
endif()
if(WQL3D_ENABLE_CUDA_AWARE_MPI AND NOT WQL3D_ENABLE_OPENACC)
  message(FATAL_ERROR "CUDA-aware MPI requires WQL3D_ENABLE_OPENACC=ON")
endif()

# Phase 1 compiles the unmodified oracle. Later phases override only files that
# actually require accelerator changes, keeping numerical drift auditable.
add_subdirectory("${WQL3D_CPU_SOURCE_DIR}/src"
                 "${CMAKE_CURRENT_BINARY_DIR}/upstream")

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
message(STATUS "  CPU oracle source: ${WQL3D_CPU_SOURCE_DIR}")
message(STATUS "  OpenACC:           ${WQL3D_ENABLE_OPENACC}")
message(STATUS "  CUDA-aware MPI:    ${WQL3D_ENABLE_CUDA_AWARE_MPI}")
if(WQL3D_ENABLE_OPENACC)
  message(STATUS "  NVIDIA GPU arch:   ${WQL3D_GPU_ARCH}")
endif()
