module rk_vector_kernels
  use common, only : wp
  implicit none
  private
  public :: scale_rate_array, update_state_array
  public :: scale_rate_array_resident, update_state_array_resident
contains
  subroutine scale_rate_array(rate, coefficient)
    real(kind=wp), allocatable, intent(inout) :: rate(:,:,:,:)
    real(kind=wp), intent(in) :: coefficient
    rate = coefficient*rate
  end subroutine scale_rate_array

  subroutine scale_rate_array_resident(rate, coefficient)
    real(kind=wp), allocatable, intent(inout) :: rate(:,:,:,:)
    real(kind=wp), intent(in) :: coefficient
    rate = coefficient*rate
  end subroutine scale_rate_array_resident

  subroutine update_state_array(state, rate, increment)
    real(kind=wp), allocatable, intent(inout) :: state(:,:,:,:)
    real(kind=wp), allocatable, intent(inout) :: rate(:,:,:,:)
    real(kind=wp), intent(in) :: increment
    if (any(shape(state) /= shape(rate))) error stop 'RK state/rate shape mismatch'
    state = state + increment*rate
  end subroutine update_state_array

  subroutine update_state_array_resident(state, rate, increment)
    real(kind=wp), allocatable, intent(inout) :: state(:,:,:,:)
    real(kind=wp), allocatable, intent(inout) :: rate(:,:,:,:)
    real(kind=wp), intent(in) :: increment
    if (any(shape(state) /= shape(rate))) error stop 'Resident RK state/rate shape mismatch'
    state = state + increment*rate
  end subroutine update_state_array_resident
end module rk_vector_kernels
