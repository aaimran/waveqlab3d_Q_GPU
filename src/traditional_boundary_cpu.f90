module traditional_boundary_backend
  use datatypes, only : block_type, mms_type
  implicit none
  private
  public :: try_traditional_lx_boundary
contains
  subroutine try_traditional_lx_boundary(B, mms_vars, handled)
    type(block_type), intent(inout) :: B
    type(mms_type), intent(in) :: mms_vars
    logical, intent(out) :: handled
    handled = .false.
  end subroutine try_traditional_lx_boundary
end module traditional_boundary_backend
