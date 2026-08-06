program openacc_runtime_probe
  use openacc
  implicit none
  real, allocatable :: values(:)

  allocate(values(8))
  values = 1.0
  call acc_copyin(values)
  if (.not.acc_is_present(values)) error stop 'acc_copyin did not establish presence'
  call acc_delete(values)
  if (acc_is_present(values)) error stop 'acc_delete did not remove presence'
  deallocate(values)
end program openacc_runtime_probe
