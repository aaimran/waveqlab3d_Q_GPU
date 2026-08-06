module rk_vector_kernels
  use common, only : wp
  use openacc
  implicit none
  private
  public :: scale_rate_array, update_state_array
contains
  subroutine scale_rate_array(rate, coefficient)
    real(kind=wp), allocatable, intent(inout) :: rate(:,:,:,:)
    real(kind=wp), intent(in) :: coefficient
    integer(kind=8) :: byte_count
    integer :: i, j, k, component

    byte_count = int(size(rate),8)*int(storage_size(0.0_wp)/8,8)
    if (.not.acc_is_present(rate, byte_count)) &
         error stop 'RK rate array is not present on device'
    call acc_update_device(rate, byte_count)
    !$acc parallel loop gang vector collapse(4) present(rate)
    do component = lbound(rate,4), ubound(rate,4)
       do k = lbound(rate,3), ubound(rate,3)
          do j = lbound(rate,2), ubound(rate,2)
             do i = lbound(rate,1), ubound(rate,1)
                rate(i,j,k,component) = coefficient*rate(i,j,k,component)
             end do
          end do
       end do
    end do
    call acc_update_self(rate, byte_count)
  end subroutine scale_rate_array

  subroutine update_state_array(state, rate, increment)
    real(kind=wp), allocatable, intent(inout) :: state(:,:,:,:)
    real(kind=wp), allocatable, intent(inout) :: rate(:,:,:,:)
    real(kind=wp), intent(in) :: increment
    integer(kind=8) :: state_bytes, rate_bytes
    integer :: i, j, k, component

    if (any(shape(state) /= shape(rate))) error stop 'RK state/rate shape mismatch'
    state_bytes = int(size(state),8)*int(storage_size(0.0_wp)/8,8)
    rate_bytes = int(size(rate),8)*int(storage_size(0.0_wp)/8,8)
    if (.not.acc_is_present(state, state_bytes) .or. &
        .not.acc_is_present(rate, rate_bytes)) &
         error stop 'RK state/rate array is not present on device'
    call acc_update_device(state, state_bytes)
    call acc_update_device(rate, rate_bytes)
    !$acc parallel loop gang vector collapse(4) present(state,rate)
    do component = lbound(state,4), ubound(state,4)
       do k = lbound(state,3), ubound(state,3)
          do j = lbound(state,2), ubound(state,2)
             do i = lbound(state,1), ubound(state,1)
                state(i,j,k,component) = state(i,j,k,component) + &
                     increment*rate(i,j,k,component)
             end do
          end do
       end do
    end do
    call acc_update_self(state, state_bytes)
  end subroutine update_state_array
end module rk_vector_kernels
