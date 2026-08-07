module traditional_cartesian_rhs_backend
  use common, only : wp
  use datatypes, only : block_type, block_grid_t, block_material
  implicit none
  private
  public :: try_traditional_cartesian_rhs
contains
  subroutine try_traditional_cartesian_rhs(F, G, M, type_of_mesh, handled)
    type(block_type), intent(inout) :: F
    type(block_grid_t), intent(in) :: G
    type(block_material), intent(inout) :: M
    character(len=*), intent(in) :: type_of_mesh
    logical, intent(out) :: handled
    handled = .false.
  end subroutine try_traditional_cartesian_rhs
end module traditional_cartesian_rhs_backend
