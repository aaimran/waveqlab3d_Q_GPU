module traditional_boundary_rhs_backend
  use datatypes, only : block_type, block_grid_t, block_material
  implicit none
  private
  public :: try_traditional_boundary_rhs
contains
  subroutine try_traditional_boundary_rhs(F,G,M,handled)
    type(block_type),intent(inout) :: F
    type(block_grid_t),intent(in) :: G
    type(block_material),intent(inout) :: M
    logical,intent(out) :: handled
    handled=.false.
  end subroutine try_traditional_boundary_rhs
end module traditional_boundary_rhs_backend
