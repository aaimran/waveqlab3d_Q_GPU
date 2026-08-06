module accelerator_runtime
  use mpi
  use common, only : wp
  use accelerator_build_config, only : accelerator_backend, &
       openacc_enabled, cuda_aware_mpi_enabled
  implicit none
  private

  integer, save :: node_comm = MPI_COMM_NULL
  integer, save :: local_rank = -1
  integer, save :: local_size = 0
  logical, save :: initialized = .false.

  public :: initialize_accelerator_runtime, finalize_accelerator_runtime, &
       enforce_device_memory_capacity

contains

  subroutine initialize_accelerator_runtime()
    integer :: ierr, world_rank

    if (initialized) return
    call MPI_Comm_rank(MPI_COMM_WORLD, world_rank, ierr)
    call MPI_Comm_split_type(MPI_COMM_WORLD, MPI_COMM_TYPE_SHARED, world_rank, &
         MPI_INFO_NULL, node_comm, ierr)
    call check_mpi(ierr, 'MPI_Comm_split_type')
    call MPI_Comm_rank(node_comm, local_rank, ierr)
    call check_mpi(ierr, 'MPI_Comm_rank(node)')
    call MPI_Comm_size(node_comm, local_size, ierr)
    call check_mpi(ierr, 'MPI_Comm_size(node)')

    if (world_rank == 0) then
      write(*,'(/,A)') 'WaveQLab3D accelerator runtime'
      write(*,'(A,A)') '  backend: ', trim(accelerator_backend)
      write(*,'(A,L1)') '  OpenACC enabled: ', openacc_enabled
      write(*,'(A,L1)') '  CUDA-aware MPI intent: ', cuda_aware_mpi_enabled
      write(*,'(A,I0)') '  working precision bits: ', storage_size(0.0_wp)
      write(*,'(A,I0)') '  MPI ranks on rank-0 node: ', local_size
    end if
    initialized = .true.
  end subroutine initialize_accelerator_runtime


  subroutine finalize_accelerator_runtime()
    integer :: ierr

    if (.not.initialized) return
    if (node_comm /= MPI_COMM_NULL) then
      call MPI_Comm_free(node_comm, ierr)
      call check_mpi(ierr, 'MPI_Comm_free(node)')
      node_comm = MPI_COMM_NULL
    end if
    initialized = .false.
  end subroutine finalize_accelerator_runtime


  subroutine enforce_device_memory_capacity(predicted_bytes)
    integer(kind=8), intent(in) :: predicted_bytes

    ! CPU runs retain the payload report but never reject a simulation based
    ! on accelerator capacity.
    if (predicted_bytes < 0_8) error stop 'negative predicted device payload'
  end subroutine enforce_device_memory_capacity


  subroutine check_mpi(ierr, operation)
    integer, intent(in) :: ierr
    character(*), intent(in) :: operation
    integer :: abort_ierr

    if (ierr == MPI_SUCCESS) return
    write(*,'(A,A,A,I0)') 'ERROR accelerator runtime: ', trim(operation), &
         ' failed with MPI code ', ierr
    call MPI_Abort(MPI_COMM_WORLD, ierr, abort_ierr)
  end subroutine check_mpi

end module accelerator_runtime
