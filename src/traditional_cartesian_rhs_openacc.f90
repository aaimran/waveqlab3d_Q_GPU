module traditional_cartesian_rhs_backend
  use common, only : wp
  use datatypes, only : block_type, block_grid_t, block_material
  use openacc
  implicit none
  private
  public :: try_traditional_cartesian_rhs
contains
  logical function try_traditional_cartesian_rhs(F, G, M, type_of_mesh)
    use mpi3dbasic, only : nprocs
    type(block_type), intent(inout) :: F
    type(block_grid_t), intent(in) :: G
    type(block_material), intent(inout) :: M
    character(len=*), intent(in) :: type_of_mesh
    integer :: n1, n2, n3
    integer(kind=8) :: field_bytes, metric_bytes, material_bytes

    try_traditional_cartesian_rhs = .false.
    if (nprocs /= 1) return
    if (trim(type_of_mesh) /= 'cartesian') return
    if (trim(F%fd_type) /= 'traditional' .or. F%order /= 6) return
    if (M%anelastic .or. M%anelastic_Q .or. M%anelastic_Q8 .or. &
        M%anelastic_Qf .or. M%anelastic_Qf8 .or. &
        M%anelastic_const_Q_4M .or. M%anelastic_const_Q_8M) return
    if (any(F%PMLB(:)%pml)) return
    if (size(F%F%F,4) /= 9 .or. size(M%M,4) < 3) return

    n1 = size(F%F%F,1); n2 = size(F%F%F,2); n3 = size(F%F%F,3)
    if (n1 < 13 .or. n2 < 13 .or. n3 < 13) return
    field_bytes = int(size(F%F%F),8)*int(storage_size(0.0_wp)/8,8)
    metric_bytes = int(size(G%metricx),8)*int(storage_size(0.0_wp)/8,8)
    material_bytes = int(size(M%M),8)*int(storage_size(0.0_wp)/8,8)
    if (.not.acc_is_present(F%F%F, field_bytes) .or. &
        .not.acc_is_present(F%F%DF, field_bytes) .or. &
        .not.acc_is_present(G%metricx, metric_bytes) .or. &
        .not.acc_is_present(G%metricy, metric_bytes) .or. &
        .not.acc_is_present(G%metricz, metric_bytes) .or. &
        .not.acc_is_present(M%M, material_bytes)) &
      error stop 'Phase 5 Cartesian RHS arrays are not present on device'

    call cartesian_elastic_o6_interior_kernel(F%F%F, F%F%DF, G%metricx, &
         G%metricy, G%metricz, M%M, n1, n2, n3, size(G%metricx,4), &
         size(M%M,4), G%hq, G%hr, G%hs)
    !$acc update self(F%F%DF)
    try_traditional_cartesian_rhs = .true.
  end function try_traditional_cartesian_rhs

  subroutine cartesian_elastic_o6_interior_kernel(field, rate, metricx, &
       metricy, metricz, material, n1, n2, n3, nm, nmat, hq, hr, hs)
    integer, intent(in) :: n1, n2, n3, nm, nmat
    real(kind=wp), intent(in) :: field(n1,n2,n3,9)
    real(kind=wp), intent(inout) :: rate(n1,n2,n3,9)
    real(kind=wp), intent(in) :: metricx(n1,n2,n3,nm)
    real(kind=wp), intent(in) :: metricy(n1,n2,n3,nm)
    real(kind=wp), intent(in) :: metricz(n1,n2,n3,nm)
    real(kind=wp), intent(in) :: material(n1,n2,n3,nmat)
    real(kind=wp), intent(in) :: hq, hr, hs
    integer :: x, y, z, s, component
    real(kind=wp) :: dfx(9), dfy(9), dfz(9), cx, cy, cz
    real(kind=wp) :: a1, a2, a3, a4, coefficient

    !$acc parallel loop gang vector collapse(3) present(field,rate,metricx,metricy,metricz,material) &
    !$acc& private(dfx,dfy,dfz,cx,cy,cz,a1,a2,a3,a4,coefficient,s,component)
    do z = 7, n3-6
      do y = 7, n2-6
        do x = 7, n1-6
          dfx = 0.0_wp; dfy = 0.0_wp; dfz = 0.0_wp
          do s = 1, 3
            if (s == 1) then
              coefficient = 0.75_wp
            else if (s == 2) then
              coefficient = -0.15_wp
            else
              coefficient = 1.0_wp/60.0_wp
            end if
            cx = coefficient/hq; cy = coefficient/hr; cz = coefficient/hs
            do component = 1, 9
              dfx(component) = dfx(component) + metricx(x,y,z,1)*cx* &
                   (field(x+s,y,z,component)-field(x-s,y,z,component))
              dfy(component) = dfy(component) + metricy(x,y,z,2)*cy* &
                   (field(x,y+s,z,component)-field(x,y-s,z,component))
              dfz(component) = dfz(component) + metricz(x,y,z,3)*cz* &
                   (field(x,y,z+s,component)-field(x,y,z-s,component))
            end do
          end do
          a1 = 1.0_wp/material(x,y,z,3)
          a2 = material(x,y,z,1) + 2.0_wp*material(x,y,z,2)
          a3 = material(x,y,z,1); a4 = material(x,y,z,2)
          rate(x,y,z,1) = rate(x,y,z,1) + a1*(dfx(4)+dfy(7)+dfz(8))
          rate(x,y,z,2) = rate(x,y,z,2) + a1*(dfx(7)+dfy(5)+dfz(9))
          rate(x,y,z,3) = rate(x,y,z,3) + a1*(dfx(8)+dfy(9)+dfz(6))
          rate(x,y,z,4) = rate(x,y,z,4) + a2*dfx(1)+a3*(dfy(2)+dfz(3))
          rate(x,y,z,5) = rate(x,y,z,5) + a2*dfy(2)+a3*(dfx(1)+dfz(3))
          rate(x,y,z,6) = rate(x,y,z,6) + a2*dfz(3)+a3*(dfx(1)+dfy(2))
          rate(x,y,z,7) = rate(x,y,z,7) + a4*(dfy(1)+dfx(2))
          rate(x,y,z,8) = rate(x,y,z,8) + a4*(dfz(1)+dfx(3))
          rate(x,y,z,9) = rate(x,y,z,9) + a4*(dfz(2)+dfy(3))
        end do
      end do
    end do
  end subroutine cartesian_elastic_o6_interior_kernel
end module traditional_cartesian_rhs_backend
