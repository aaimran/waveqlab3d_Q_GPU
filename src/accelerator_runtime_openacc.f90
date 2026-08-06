module accelerator_runtime
  use mpi
  use openacc
  use common, only : wp
  use accelerator_build_config, only : accelerator_backend, &
       openacc_enabled, cuda_aware_mpi_enabled
  implicit none
  private

  integer, save :: node_comm = MPI_COMM_NULL
  integer, save :: local_rank = -1
  integer, save :: local_size = 0
  integer, save :: device_count = 0
  integer, save :: selected_device = -1
  logical, save :: initialized = .false.

  public :: initialize_accelerator_runtime, finalize_accelerator_runtime

contains

  subroutine initialize_accelerator_runtime()
    integer :: ierr, world_rank, world_size, report_rank
    logical :: allow_oversubscription

    if (initialized) return
    call MPI_Comm_rank(MPI_COMM_WORLD, world_rank, ierr)
    call check_mpi(ierr, 'MPI_Comm_rank(world)')
    call MPI_Comm_size(MPI_COMM_WORLD, world_size, ierr)
    call check_mpi(ierr, 'MPI_Comm_size(world)')
    call MPI_Comm_split_type(MPI_COMM_WORLD, MPI_COMM_TYPE_SHARED, world_rank, &
         MPI_INFO_NULL, node_comm, ierr)
    call check_mpi(ierr, 'MPI_Comm_split_type')
    call MPI_Comm_rank(node_comm, local_rank, ierr)
    call check_mpi(ierr, 'MPI_Comm_rank(node)')
    call MPI_Comm_size(node_comm, local_size, ierr)
    call check_mpi(ierr, 'MPI_Comm_size(node)')

    device_count = acc_get_num_devices(acc_device_nvidia)
    if (device_count < 1) then
      if (local_rank == 0) write(*,'(A)') &
           'ERROR accelerator runtime: no NVIDIA OpenACC device is visible'
      call MPI_Abort(MPI_COMM_WORLD, 91, ierr)
    end if

    allow_oversubscription = environment_true('WQL3D_ALLOW_GPU_OVERSUBSCRIPTION')
    if (local_size > device_count .and. .not.allow_oversubscription) then
      if (local_rank == 0) then
        write(*,'(A,I0,A,I0)') 'ERROR accelerator runtime: local MPI ranks=', &
             local_size, ' exceed visible GPUs=', device_count
        write(*,'(A)') '  Request one GPU per local rank or explicitly set'
        write(*,'(A)') '  WQL3D_ALLOW_GPU_OVERSUBSCRIPTION=1 for tests only.'
      end if
      call MPI_Abort(MPI_COMM_WORLD, 92, ierr)
    end if

    selected_device = modulo(local_rank, device_count)
    call acc_set_device_num(selected_device, acc_device_nvidia)
    call acc_init(acc_device_nvidia)
    selected_device = acc_get_device_num(acc_device_nvidia)

    if (world_rank == 0) then
      write(*,'(/,A)') 'WaveQLab3D accelerator runtime'
      write(*,'(A,A)') '  backend: ', trim(accelerator_backend)
      write(*,'(A,L1)') '  OpenACC enabled: ', openacc_enabled
      write(*,'(A,L1)') '  CUDA-aware MPI intent: ', cuda_aware_mpi_enabled
      write(*,'(A,I0)') '  working precision bits: ', storage_size(0.0_wp)
      write(*,'(A,I0)') '  global MPI ranks: ', world_size
    end if

    ! Ordered startup output makes multi-rank binding auditable.
    do report_rank = 0, world_size - 1
      call MPI_Barrier(MPI_COMM_WORLD, ierr)
      call check_mpi(ierr, 'MPI_Barrier(report)')
      if (world_rank == report_rank) then
        write(*,'(A,I0,A,I0,A,I0,A,I0)') '  rank ', world_rank, &
             ': local_rank=', local_rank, ', visible_gpus=', device_count, &
             ', selected_gpu=', selected_device
        flush(6)
      end if
    end do
    call MPI_Barrier(MPI_COMM_WORLD, ierr)
    call check_mpi(ierr, 'MPI_Barrier(report final)')

    initialized = .true.
  end subroutine initialize_accelerator_runtime


  subroutine finalize_accelerator_runtime()
    integer :: ierr

    if (.not.initialized) return
    call acc_shutdown(acc_device_nvidia)
    if (node_comm /= MPI_COMM_NULL) then
      call MPI_Comm_free(node_comm, ierr)
      call check_mpi(ierr, 'MPI_Comm_free(node)')
      node_comm = MPI_COMM_NULL
    end if
    initialized = .false.
  end subroutine finalize_accelerator_runtime


  logical function environment_true(name)
    character(*), intent(in) :: name
    character(16) :: value
    integer :: status

    value = ''
    call get_environment_variable(name, value, status=status)
    environment_true = status == 0 .and. &
         any(trim(adjustl(value)) == [character(len=5) :: &
         '1', 'true', 'TRUE', 'yes', 'YES'])
  end function environment_true


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

