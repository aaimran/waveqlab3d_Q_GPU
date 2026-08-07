module traditional_cartesian_rhs_backend
  use common, only : wp
  use datatypes, only : block_type, block_grid_t, block_material
  use openacc
  implicit none
  private
  public :: try_traditional_cartesian_rhs
contains
  subroutine try_traditional_cartesian_rhs(F, G, M, type_of_mesh, handled)
    use mpi3dbasic, only : nprocs
    type(block_type), intent(inout) :: F
    type(block_grid_t), intent(in) :: G
    type(block_material), intent(inout) :: M
    character(len=*), intent(in) :: type_of_mesh
    logical, intent(out) :: handled
    integer :: n1, n2, n3, xlo, xhi, ylo, yhi, zlo, zhi
    integer(kind=8) :: field_bytes, metric_bytes, material_bytes

    handled = .false.
    if (nprocs /= 1) return
    if (trim(type_of_mesh) /= 'cartesian') return
    if (trim(F%fd_type) /= 'traditional' .or. F%order /= 6) return
    if (M%anelastic .or. M%anelastic_Q .or. M%anelastic_Q8 .or. &
        M%anelastic_Qf .or. M%anelastic_Qf8 .or. &
        M%anelastic_const_Q_4M .or. M%anelastic_const_Q_8M) return
    if (any(F%PMLB(:)%pml)) return
    if (.not.allocated(F%F%F) .or. .not.allocated(F%F%DF) .or. &
        .not.allocated(G%metricx) .or. .not.allocated(G%metricy) .or. &
        .not.allocated(G%metricz) .or. .not.allocated(M%M)) return
    if (environment_true('WQL3D_PHASE5_DIAGNOSTICS')) then
      write(*,'(A,6(I0,1X))') 'Phase 5 field bounds: ', &
           lbound(F%F%F,1), ubound(F%F%F,1), lbound(F%F%F,2), &
           ubound(F%F%F,2), lbound(F%F%F,3), ubound(F%F%F,3)
      write(*,'(A,9(I0,1X))') 'Phase 5 grid indices: ', G%C%mq, G%C%pq, &
           G%C%mr, G%C%pr, G%C%ms, G%C%ps, G%C%nq, G%C%nr, G%C%ns
      write(*,'(A,4(I0,1X))') 'Phase 5 field shape: ', shape(F%F%F)
      write(*,'(A,4(I0,1X))') 'Phase 5 rate shape: ', shape(F%F%DF)
      write(*,'(A,4(I0,1X))') 'Phase 5 metric shape: ', shape(G%metricx)
      write(*,'(A,4(I0,1X))') 'Phase 5 metric-y shape: ', shape(G%metricy)
      write(*,'(A,4(I0,1X))') 'Phase 5 metric-z shape: ', shape(G%metricz)
      write(*,'(A,4(I0,1X))') 'Phase 5 material shape: ', shape(M%M)
      write(*,'(A,4(I0,1X))') 'Phase 5 rate lower bounds: ', lbound(F%F%DF)
      write(*,'(A,4(I0,1X))') 'Phase 5 metric lower bounds: ', lbound(G%metricx)
      write(*,'(A,4(I0,1X))') 'Phase 5 metric-y lower bounds: ', lbound(G%metricy)
      write(*,'(A,4(I0,1X))') 'Phase 5 metric-z lower bounds: ', lbound(G%metricz)
      write(*,'(A,4(I0,1X))') 'Phase 5 material lower bounds: ', lbound(M%M)
    end if
    if (size(F%F%F,4) /= 9 .or. size(M%M,4) < 3) return
    if (any(shape(F%F%DF) /= shape(F%F%F))) return
    if (any(shape(G%metricx, kind=8) /= shape(G%metricy, kind=8)) .or. &
        any(shape(G%metricx, kind=8) /= shape(G%metricz, kind=8))) return
    if (size(G%metricx,1) /= size(F%F%F,1) .or. &
        size(G%metricx,2) /= size(F%F%F,2) .or. &
        size(G%metricx,3) /= size(F%F%F,3)) return
    if (size(M%M,1) /= size(F%F%F,1) .or. &
        size(M%M,2) /= size(F%F%F,2) .or. &
        size(M%M,3) /= size(F%F%F,3)) return
    if (any(lbound(F%F%DF) /= lbound(F%F%F))) return
    if (lbound(G%metricx,1) /= lbound(F%F%F,1) .or. &
        lbound(G%metricx,2) /= lbound(F%F%F,2) .or. &
        lbound(G%metricx,3) /= lbound(F%F%F,3)) return
    if (lbound(G%metricy,1) /= lbound(F%F%F,1) .or. &
        lbound(G%metricy,2) /= lbound(F%F%F,2) .or. &
        lbound(G%metricy,3) /= lbound(F%F%F,3)) return
    if (lbound(G%metricz,1) /= lbound(F%F%F,1) .or. &
        lbound(G%metricz,2) /= lbound(F%F%F,2) .or. &
        lbound(G%metricz,3) /= lbound(F%F%F,3)) return
    if (lbound(M%M,1) /= lbound(F%F%F,1) .or. &
        lbound(M%M,2) /= lbound(F%F%F,2) .or. &
        lbound(M%M,3) /= lbound(F%F%F,3)) return
    if (G%C%mq < lbound(F%F%F,1) .or. G%C%pq > ubound(F%F%F,1) .or. &
        G%C%mr < lbound(F%F%F,2) .or. G%C%pr > ubound(F%F%F,2) .or. &
        G%C%ms < lbound(F%F%F,3) .or. G%C%ps > ubound(F%F%F,3)) return

    n1 = size(F%F%F,1); n2 = size(F%F%F,2); n3 = size(F%F%F,3)
    if (n1 < 13 .or. n2 < 13 .or. n3 < 13) return
    xlo = 7 - lbound(F%F%F,1) + 1
    xhi = G%C%nq - 6 - lbound(F%F%F,1) + 1
    ylo = 7 - lbound(F%F%F,2) + 1
    yhi = G%C%nr - 6 - lbound(F%F%F,2) + 1
    zlo = 7 - lbound(F%F%F,3) + 1
    zhi = G%C%ns - 6 - lbound(F%F%F,3) + 1
    if (xlo < 4 .or. xhi > n1-3 .or. xlo > xhi .or. &
        ylo < 4 .or. yhi > n2-3 .or. ylo > yhi .or. &
        zlo < 4 .or. zhi > n3-3 .or. zlo > zhi) return
    if (environment_true('WQL3D_PHASE5_DIAGNOSTICS')) &
         write(*,'(A,6(I0,1X))') 'Phase 5 raw interior bounds: ', &
         xlo, xhi, ylo, yhi, zlo, zhi
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
         size(M%M,4), xlo, xhi, ylo, yhi, zlo, zhi, G%hq, G%hr, G%hs)
    !$acc update self(F%F%DF)
    handled = .true.
  end subroutine try_traditional_cartesian_rhs

  subroutine cartesian_elastic_o6_interior_kernel(field, rate, metricx, &
       metricy, metricz, material, n1, n2, n3, nm, nmat, &
       xlo, xhi, ylo, yhi, zlo, zhi, hq, hr, hs)
    integer, intent(in) :: n1, n2, n3, nm, nmat
    integer, intent(in) :: xlo, xhi, ylo, yhi, zlo, zhi
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
    do z = zlo, zhi
      do y = ylo, yhi
        do x = xlo, xhi
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

  logical function environment_true(name)
    character(*), intent(in) :: name
    character(16) :: value
    integer :: status
    value = ''
    call get_environment_variable(name, value, status=status)
    environment_true = status == 0 .and. any(trim(adjustl(value)) == &
         [character(len=5) :: '1', 'true', 'TRUE', 'yes', 'YES'])
  end function environment_true
end module traditional_cartesian_rhs_backend
