module rk_vector_test_data
  use common, only : wp
  use openacc
  implicit none
contains
  subroutine enter_test_data(state, rate)
    real(kind=wp), allocatable, intent(inout) :: state(:,:,:,:), rate(:,:,:,:)
    !$acc enter data copyin(state,rate)
  end subroutine
  subroutine exit_test_data(state, rate)
    real(kind=wp), allocatable, intent(inout) :: state(:,:,:,:), rate(:,:,:,:)
    !$acc exit data delete(rate,state) finalize
  end subroutine
end module rk_vector_test_data
