module rk_vector_test_data
  use common, only : wp
  use openacc
  implicit none
contains
  subroutine enter_test_data(state, rate)
    real(kind=wp), allocatable, intent(inout) :: state(:,:,:,:), rate(:,:,:,:)
    integer(kind=8) :: state_bytes, rate_bytes
    state_bytes=int(size(state),8)*int(storage_size(0.0_wp)/8,8)
    rate_bytes=int(size(rate),8)*int(storage_size(0.0_wp)/8,8)
    call acc_copyin(state,state_bytes)
    call acc_copyin(rate,rate_bytes)
  end subroutine
  subroutine exit_test_data(state, rate)
    real(kind=wp), allocatable, intent(inout) :: state(:,:,:,:), rate(:,:,:,:)
    integer(kind=8) :: state_bytes, rate_bytes
    state_bytes=int(size(state),8)*int(storage_size(0.0_wp)/8,8)
    rate_bytes=int(size(rate),8)*int(storage_size(0.0_wp)/8,8)
    call acc_delete_finalize(rate,rate_bytes)
    call acc_delete_finalize(state,state_bytes)
  end subroutine
end module rk_vector_test_data
