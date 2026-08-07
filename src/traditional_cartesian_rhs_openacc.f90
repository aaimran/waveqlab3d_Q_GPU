module traditional_cartesian_rhs_backend
  use common, only : wp
  use datatypes, only : block_type, block_grid_t, block_material
  use openacc
  implicit none
  private
  public :: try_traditional_cartesian_rhs, traditional_cartesian_rhs_includes_boundaries
  logical :: boundaries_completed = .false.
contains
  subroutine try_traditional_cartesian_rhs(F, G, M, type_of_mesh, handled)
    use mpi3dbasic, only : nprocs
    type(block_type), intent(inout) :: F
    type(block_grid_t), intent(in) :: G
    type(block_material), intent(inout) :: M
    character(len=*), intent(in) :: type_of_mesh
    logical, intent(out) :: handled
    integer :: n1, n2, n3
    integer(kind=8) :: field_bytes, metric_bytes, material_bytes

    handled = .false.
    boundaries_completed = .false.
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
    handled = .true.
    boundaries_completed = .true.
  end subroutine try_traditional_cartesian_rhs

  logical function traditional_cartesian_rhs_includes_boundaries()
    traditional_cartesian_rhs_includes_boundaries = boundaries_completed
    boundaries_completed = .false.
  end function traditional_cartesian_rhs_includes_boundaries

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
    do z = 1, n3
      do y = 1, n2
        do x = 1, n1
          dfx = 0.0_wp; dfy = 0.0_wp; dfz = 0.0_wp
          do s = 1, 3
            if (s == 1) then
              coefficient = 0.75_wp
            else if (s == 2) then
              coefficient = -0.15_wp
            else
              coefficient = 1.0_wp/60.0_wp
            end if
            do component = 1, 9
              if (x >= 7 .and. x <= n1-6) dfx(component) = dfx(component) + &
                   metricx(x,y,z,1)*(coefficient/hq)* &
                   (field(x+s,y,z,component)-field(x-s,y,z,component))
              if (y >= 7 .and. y <= n2-6) dfy(component) = dfy(component) + &
                   metricy(x,y,z,2)*(coefficient/hr)* &
                   (field(x,y+s,z,component)-field(x,y-s,z,component))
              if (z >= 7 .and. z <= n3-6) dfz(component) = dfz(component) + &
                   metricz(x,y,z,3)*(coefficient/hs)* &
                   (field(x,y,z+s,component)-field(x,y,z-s,component))
            end do
          end do
          if (x <= 6 .or. x > n1-6) then
            do component=1,9
              dfx(component)=metricx(x,y,z,1)*boundary_derivative_x(field,n1,n2,n3,x,y,z,component)/hq
            end do
          end if
          if (y <= 6 .or. y > n2-6) then
            do component=1,9
              dfy(component)=metricy(x,y,z,2)*boundary_derivative_y(field,n1,n2,n3,x,y,z,component)/hr
            end do
          end if
          if (z <= 6 .or. z > n3-6) then
            do component=1,9
              dfz(component)=metricz(x,y,z,3)*boundary_derivative_z(field,n1,n2,n3,x,y,z,component)/hs
            end do
          end if
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

  !$acc routine seq
  real(kind=wp) function sbp6_weight(point, sample, n)
    integer, intent(in) :: point, sample, n
    integer :: row, col
    real(kind=wp), parameter :: w(6,9) = reshape([ &
      -1.582533518939116_wp,-0.462059195631158_wp, 0.071247104721830_wp, 0.114713313798970_wp,-0.036210680656541_wp,-0.011398193015050_wp, &
       2.033378678700676_wp, 0.0_wp,-0.636451095137907_wp,-0.290087484386815_wp, 0.105400944933782_wp, 0.020437334208704_wp, &
      -0.141512858744873_wp, 0.287258622978251_wp, 0.0_wp,-0.306681191361148_wp, 0.015764336127392_wp, 0.011220896474665_wp, &
      -0.450398306578272_wp, 0.258816087376832_wp, 0.606235523609147_wp, 0.0_wp,-0.707905442575989_wp, 0.063183694641876_wp, &
       0.104488069284042_wp,-0.069112065532624_wp,-0.022902190275815_wp, 0.520262285050482_wp, 0.0_wp,-0.691649024426814_wp, &
       0.036577936277544_wp,-0.014903449191300_wp,-0.018129342917256_wp,-0.051642265516119_wp, 0.769199413962647_wp, 0.0_wp, &
       0.0_wp,0.0_wp,0.0_wp,0.013435342414630_wp,-0.164529643265203_wp,0.739709139060752_wp, &
       0.0_wp,0.0_wp,0.0_wp,0.0_wp,0.018281071473911_wp,-0.147941827812150_wp, &
       0.0_wp,0.0_wp,0.0_wp,0.0_wp,0.0_wp,0.016437980868017_wp ], [6,9])
    if (point <= 6) then
      row=point; col=sample
      sbp6_weight=w(row,col)
    else
      row=n-point+1; col=n-sample+1
      sbp6_weight=-w(row,col)
    end if
  end function sbp6_weight

  !$acc routine seq
  real(kind=wp) function boundary_derivative_x(f,n1,n2,n3,x,y,z,c)
    integer,intent(in)::n1,n2,n3,x,y,z,c
    real(kind=wp),intent(in)::f(n1,n2,n3,9)
    integer::q,sample
    boundary_derivative_x=0.0_wp
    do q=1,9
      sample=q
      if (x > n1-6) sample=n1-9+q
      boundary_derivative_x=boundary_derivative_x+sbp6_weight(x,sample,n1)*f(sample,y,z,c)
    end do
  end function boundary_derivative_x

  !$acc routine seq
  real(kind=wp) function boundary_derivative_y(f,n1,n2,n3,x,y,z,c)
    integer,intent(in)::n1,n2,n3,x,y,z,c
    real(kind=wp),intent(in)::f(n1,n2,n3,9)
    integer::q,sample
    boundary_derivative_y=0.0_wp
    do q=1,9
      sample=q
      if (y > n2-6) sample=n2-9+q
      boundary_derivative_y=boundary_derivative_y+sbp6_weight(y,sample,n2)*f(x,sample,z,c)
    end do
  end function boundary_derivative_y

  !$acc routine seq
  real(kind=wp) function boundary_derivative_z(f,n1,n2,n3,x,y,z,c)
    integer,intent(in)::n1,n2,n3,x,y,z,c
    real(kind=wp),intent(in)::f(n1,n2,n3,9)
    integer::q,sample
    boundary_derivative_z=0.0_wp
    do q=1,9
      sample=q
      if (z > n3-6) sample=n3-9+q
      boundary_derivative_z=boundary_derivative_z+sbp6_weight(z,sample,n3)*f(x,y,sample,c)
    end do
  end function boundary_derivative_z
end module traditional_cartesian_rhs_backend
