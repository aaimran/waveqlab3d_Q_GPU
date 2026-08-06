module allocation_tracking
  use, intrinsic :: iso_c_binding, only : c_int64_t
  use mpi
  implicit none
  private
  public :: begin_timestep_allocation_tracking, end_timestep_allocation_tracking

  interface
    subroutine tracker_begin() bind(C, name='wql3d_allocation_tracker_begin')
    end subroutine tracker_begin
    function tracker_end() result(count) bind(C, name='wql3d_allocation_tracker_end')
      import :: c_int64_t
      integer(c_int64_t) :: count
    end function tracker_end
  end interface
contains
  subroutine begin_timestep_allocation_tracking()
    call tracker_begin()
  end subroutine begin_timestep_allocation_tracking

  subroutine end_timestep_allocation_tracking()
    integer(c_int64_t) :: local_count, global_count, maximum_count
    integer :: ierr, rank

    local_count = tracker_end()
    call MPI_Allreduce(local_count, global_count, 1, MPI_INTEGER8, MPI_SUM, MPI_COMM_WORLD, ierr)
    call MPI_Allreduce(local_count, maximum_count, 1, MPI_INTEGER8, MPI_MAX, MPI_COMM_WORLD, ierr)
    call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr)
    if (rank == 0) then
      write(*,'(A)') 'Steady-state allocation tracker:'
      write(*,'(A,I0)') '  aggregate allocation calls: ', global_count
      write(*,'(A,I0)') '  maximum per rank:           ', maximum_count
      write(*,'(A,A)') '  decision:                   ', merge('FAIL', 'PASS', global_count /= 0)
      flush(6)
    end if
    if (global_count /= 0) then
      if (rank == 0) write(*,'(A)') 'FATAL  RUN-ALLOC-001: heap allocation occurred during timestepping.'
      call MPI_Abort(MPI_COMM_WORLD, 95, ierr)
    end if
  end subroutine end_timestep_allocation_tracking
end module allocation_tracking
