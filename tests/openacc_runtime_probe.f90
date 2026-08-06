program openacc_runtime_probe
  use openacc
  implicit none
  real, allocatable :: values(:)

  allocate(values(8))
  values = 1.0
  call map_and_unmap(values)
  deallocate(values)
contains
  subroutine map_and_unmap(value)
    real, allocatable, intent(inout) :: value(:)
    integer(kind=8) :: byte_count
    byte_count = int(size(value),8)*int(storage_size(0.0)/8,8)
    call acc_copyin(value, byte_count)
    if (.not.acc_is_present(value, byte_count)) &
         error stop 'acc_copyin did not establish presence'
    call acc_delete_finalize(value, byte_count)
    if (acc_is_present(value, byte_count)) &
         error stop 'acc_delete_finalize did not remove presence'
  end subroutine map_and_unmap
end program openacc_runtime_probe
