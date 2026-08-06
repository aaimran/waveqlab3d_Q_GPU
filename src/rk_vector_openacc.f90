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

    byte_count = int(size(rate),8)*int(storage_size(0.0_wp)/8,8)
    if (.not.acc_is_present(rate, byte_count)) &
         error stop 'RK rate array is not present on device'
    !$acc update device(rate)
    call scale_rate_kernel(rate, size(rate,1), size(rate,2), size(rate,3), &
         size(rate,4), coefficient)
    !$acc update self(rate)
  end subroutine scale_rate_array

  subroutine scale_rate_kernel(rate, n1, n2, n3, n4, coefficient)
    integer, intent(in) :: n1, n2, n3, n4
    real(kind=wp), intent(inout) :: rate(n1,n2,n3,n4)
    real(kind=wp), intent(in) :: coefficient
    integer :: i, j, k, component
    !$acc parallel loop gang vector collapse(4) present(rate)
    do component = 1, n4
       do k = 1, n3
          do j = 1, n2
             do i = 1, n1
                rate(i,j,k,component) = coefficient*rate(i,j,k,component)
             end do
          end do
       end do
    end do
  end subroutine scale_rate_kernel

  subroutine update_state_array(state, rate, increment)
    real(kind=wp), allocatable, intent(inout) :: state(:,:,:,:)
    real(kind=wp), allocatable, intent(inout) :: rate(:,:,:,:)
    real(kind=wp), intent(in) :: increment
    integer(kind=8) :: state_bytes, rate_bytes

    if (any(shape(state) /= shape(rate))) error stop 'RK state/rate shape mismatch'
    state_bytes = int(size(state),8)*int(storage_size(0.0_wp)/8,8)
    rate_bytes = int(size(rate),8)*int(storage_size(0.0_wp)/8,8)
    if (.not.acc_is_present(state, state_bytes) .or. &
        .not.acc_is_present(rate, rate_bytes)) &
         error stop 'RK state/rate array is not present on device'
    !$acc update device(state)
    !$acc update device(rate)
    call update_state_kernel(state, rate, size(state,1), size(state,2), &
         size(state,3), size(state,4), increment)
    !$acc update self(state)
  end subroutine update_state_array

  subroutine update_state_kernel(state, rate, n1, n2, n3, n4, increment)
    integer, intent(in) :: n1, n2, n3, n4
    real(kind=wp), intent(inout) :: state(n1,n2,n3,n4)
    real(kind=wp), intent(in) :: rate(n1,n2,n3,n4)
    real(kind=wp), intent(in) :: increment
    integer :: i, j, k, component
    !$acc parallel loop gang vector collapse(4) present(state,rate)
    do component = 1, n4
       do k = 1, n3
          do j = 1, n2
             do i = 1, n1
                state(i,j,k,component) = state(i,j,k,component) + &
                     increment*rate(i,j,k,component)
             end do
          end do
       end do
    end do
  end subroutine update_state_kernel
end module rk_vector_kernels
