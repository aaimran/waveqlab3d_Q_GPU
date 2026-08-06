module rk_vector_test_data
  use common, only : wp
  implicit none
contains
  subroutine enter_test_data(state, rate)
    real(kind=wp), allocatable, intent(inout) :: state(:,:,:,:), rate(:,:,:,:)
    if (size(state) + size(rate) < 0) error stop 'invalid test arrays'
  end subroutine
  subroutine exit_test_data(state, rate)
    real(kind=wp), allocatable, intent(inout) :: state(:,:,:,:), rate(:,:,:,:)
    if (size(state) + size(rate) < 0) error stop 'invalid test arrays'
  end subroutine
end module rk_vector_test_data
