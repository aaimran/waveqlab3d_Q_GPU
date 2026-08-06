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

  public :: initialize_accelerator_runtime, finalize_accelerator_runtime, &
       enforce_device_memory_capacity

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


  subroutine enforce_device_memory_capacity(predicted_bytes)
    use, intrinsic :: iso_fortran_env, only : int64, error_unit
    use, intrinsic :: ieee_arithmetic, only : ieee_is_finite
    integer(int64), intent(in) :: predicted_bytes
    integer(int64), parameter :: default_fixed_reserve = 1073741824_int64
    real(kind=wp), parameter :: default_fractional_reserve = 0.10_wp
    integer(int64) :: capacity_bytes, fixed_reserve, fractional_bytes
    integer(int64) :: usable_bytes, remaining_bytes
    integer(int64) :: maximum_predicted
    real(kind=wp) :: fractional_reserve
    integer :: ierr, world_rank, parse_status, local_failure, any_failure

    call MPI_Comm_rank(MPI_COMM_WORLD, world_rank, ierr)
    call check_mpi(ierr, 'MPI_Comm_rank(memory capacity)')
    call MPI_Allreduce(predicted_bytes, maximum_predicted, 1, MPI_INTEGER8, &
         MPI_MAX, MPI_COMM_WORLD, ierr)
    call check_mpi(ierr, 'MPI_Allreduce(memory payload)')

    call read_environment_int64('WQL3D_GPU_MEMORY_BYTES', capacity_bytes, &
         parse_status, required=.true.)
    if (parse_status /= 0) then
      if (world_rank == 0) then
        write(error_unit,'(/,A)') 'FATAL  RUN-GPU-MEM-001'
        write(error_unit,'(A)') '  WQL3D_GPU_MEMORY_BYTES must be set to a positive integer byte count.'
        write(error_unit,'(A)') '  Capacity enforcement requires an explicit, deterministic device capacity.'
        flush(error_unit)
      end if
      call MPI_Abort(MPI_COMM_WORLD, 93, ierr)
    end if

    fixed_reserve = default_fixed_reserve
    call read_environment_int64('WQL3D_GPU_MEMORY_FIXED_RESERVE_BYTES', &
         fixed_reserve, parse_status, required=.false.)
    if (parse_status /= 0) call memory_configuration_error( &
         'WQL3D_GPU_MEMORY_FIXED_RESERVE_BYTES must be a nonnegative integer.', world_rank)

    fractional_reserve = default_fractional_reserve
    call read_environment_real('WQL3D_GPU_MEMORY_RESERVE_FRACTION', &
         fractional_reserve, parse_status)
    if (parse_status /= 0 .or. .not.ieee_is_finite(fractional_reserve) .or. &
         fractional_reserve < 0.0_wp .or. &
         fractional_reserve >= 1.0_wp) call memory_configuration_error( &
         'WQL3D_GPU_MEMORY_RESERVE_FRACTION must be in [0,1).', world_rank)

    fractional_bytes = int(real(capacity_bytes, wp) * fractional_reserve, int64)
    usable_bytes = max(0_int64, capacity_bytes - fixed_reserve - fractional_bytes)
    remaining_bytes = usable_bytes - maximum_predicted
    local_failure = merge(1, 0, predicted_bytes > usable_bytes)
    call MPI_Allreduce(local_failure, any_failure, 1, MPI_INTEGER, MPI_MAX, &
         MPI_COMM_WORLD, ierr)
    call check_mpi(ierr, 'MPI_Allreduce(memory decision)')

    if (world_rank == 0) then
      write(*,'(A)') 'GPU memory capacity preflight:'
      write(*,'(A,F12.3,A)') '  predicted persistent payload: ', &
           real(maximum_predicted,wp)/1048576.0_wp, ' MiB'
      write(*,'(A,F12.3,A)') '  configured device capacity:  ', &
           real(capacity_bytes,wp)/1048576.0_wp, ' MiB'
      write(*,'(A,F12.3,A)') '  fixed reserve:               ', &
           real(fixed_reserve,wp)/1048576.0_wp, ' MiB'
      write(*,'(A,F12.3,A,F6.2,A)') '  fractional reserve:          ', &
           real(fractional_bytes,wp)/1048576.0_wp, ' MiB (', &
           100.0_wp*fractional_reserve, '%)'
      write(*,'(A,F12.3,A)') '  usable capacity:             ', &
           real(usable_bytes,wp)/1048576.0_wp, ' MiB'
      write(*,'(A,F12.3,A)') '  remaining headroom:          ', &
           real(remaining_bytes,wp)/1048576.0_wp, ' MiB'
      write(*,'(A,A)') '  decision:                    ', &
           merge('FAIL', 'PASS', any_failure /= 0)
      flush(6)
    end if

    if (any_failure /= 0) then
      if (world_rank == 0) then
        write(error_unit,'(/,A)') 'FATAL  RUN-GPU-MEM-002'
        write(error_unit,'(A)') '  Predicted persistent device payload exceeds usable GPU capacity.'
        flush(error_unit)
      end if
      call MPI_Abort(MPI_COMM_WORLD, 94, ierr)
    end if
  end subroutine enforce_device_memory_capacity


  subroutine read_environment_int64(name, value, parse_status, required)
    use, intrinsic :: iso_fortran_env, only : int64
    character(*), intent(in) :: name
    integer(int64), intent(inout) :: value
    integer, intent(out) :: parse_status
    logical, intent(in) :: required
    character(len=128) :: text
    integer :: env_status

    text = ''
    call get_environment_variable(name, text, status=env_status)
    if (env_status /= 0 .or. len_trim(text) == 0) then
      parse_status = merge(1, 0, required)
      return
    end if
    read(text, *, iostat=parse_status) value
    if (parse_status == 0 .and. value < 0_int64) parse_status = 1
    if (required .and. value == 0_int64) parse_status = 1
  end subroutine read_environment_int64


  subroutine read_environment_real(name, value, parse_status)
    character(*), intent(in) :: name
    real(kind=wp), intent(inout) :: value
    integer, intent(out) :: parse_status
    character(len=128) :: text
    integer :: env_status

    text = ''
    call get_environment_variable(name, text, status=env_status)
    if (env_status /= 0 .or. len_trim(text) == 0) then
      parse_status = 0
      return
    end if
    read(text, *, iostat=parse_status) value
  end subroutine read_environment_real


  subroutine memory_configuration_error(message, world_rank)
    use, intrinsic :: iso_fortran_env, only : error_unit
    character(*), intent(in) :: message
    integer, intent(in) :: world_rank
    integer :: ierr

    if (world_rank == 0) then
      write(error_unit,'(/,A)') 'FATAL  RUN-GPU-MEM-001'
      write(error_unit,'(A,A)') '  ', trim(message)
      flush(error_unit)
    end if
    call MPI_Abort(MPI_COMM_WORLD, 93, ierr)
  end subroutine memory_configuration_error


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
