module rk_vector_kernels
  use common, only : wp
  implicit none
  private
  public :: scale_rate_array, update_state_array
contains
  subroutine scale_rate_array(rate, coefficient)
    real(kind=wp), allocatable, intent(inout) :: rate(:,:,:,:)
    real(kind=wp), intent(in) :: coefficient
    rate = coefficient*rate
  end subroutine scale_rate_array

  subroutine update_state_array(state, rate, increment)
    real(kind=wp), allocatable, intent(inout) :: state(:,:,:,:)
    real(kind=wp), allocatable, intent(inout) :: rate(:,:,:,:)
    real(kind=wp), intent(in) :: increment
    if (any(shape(state) /= shape(rate))) error stop 'RK state/rate shape mismatch'
    state = state + increment*rate
  end subroutine update_state_array
end module rk_vector_kernels
