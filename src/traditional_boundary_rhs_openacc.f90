module traditional_boundary_rhs_backend
  use common, only : wp
  use datatypes, only : block_type, block_grid_t, block_material
  use openacc
  implicit none
  private
  public :: try_traditional_boundary_rhs
  logical,save :: reported=.false.
contains
  subroutine try_traditional_boundary_rhs(F,G,M,handled)
    use mpi3dbasic, only : nprocs
    type(block_type),intent(inout) :: F
    type(block_grid_t),intent(in) :: G
    type(block_material),intent(inout) :: M
    logical,intent(out) :: handled
    integer :: n1,n2,n3,x0,y0,z0
    integer(kind=8) :: fb,mb,jb
    handled=.false.
    if (nprocs /= 1 .or. trim(F%fd_type) /= 'traditional' .or. F%order /= 6) return
    if (any(F%PMLB(:)%pml)) return
    if (M%anelastic .or. M%anelastic_Q .or. M%anelastic_Q8 .or. M%anelastic_Qf .or. &
        M%anelastic_Qf8 .or. M%anelastic_const_Q_4M .or. M%anelastic_const_Q_8M) return
    if (G%C%mq /= 1 .or. G%C%pq /= G%C%nq .or. G%C%mr /= 1 .or. &
        G%C%pr /= G%C%nr .or. G%C%ms /= 1 .or. G%C%ps /= G%C%ns) return
    if (min(G%C%nq,G%C%nr,G%C%ns) < 13) return
    n1=size(F%F%F,1); n2=size(F%F%F,2); n3=size(F%F%F,3)
    x0=1-lbound(F%F%F,1)+1; y0=1-lbound(F%F%F,2)+1; z0=1-lbound(F%F%F,3)+1
    if (x0 < 1 .or. x0+G%C%nq-1 > n1 .or. y0 < 1 .or. &
        y0+G%C%nr-1 > n2 .or. z0 < 1 .or. z0+G%C%ns-1 > n3) return
    fb=int(size(F%F%F),8)*int(storage_size(0.0_wp)/8,8)
    mb=int(size(M%M),8)*int(storage_size(0.0_wp)/8,8)
    jb=int(size(G%J),8)*int(storage_size(0.0_wp)/8,8)
    if (.not.acc_is_present(F%F%F,fb) .or. .not.acc_is_present(F%F%DF,fb) .or. &
        .not.acc_is_present(M%M,mb) .or. .not.acc_is_present(G%J,jb)) &
      error stop 'Phase 6 SBP arrays absent from device'
    call boundary_rhs_kernel(F%F%F,F%F%DF,M%M,G%J,G%metricx,G%metricy,G%metricz, &
         n1,n2,n3,size(M%M,4),size(G%metricx,4),G%C%nq,G%C%nr,G%C%ns, &
         x0,y0,z0,G%hq,G%hr,G%hs)
    !$acc update self(F%F%DF)
    if (environment_true('WQL3D_PHASE6_DIAGNOSTICS') .and. .not.reported) then
      write(*,'(A,3(I0,1X))') 'Phase 6 SBP boundary launch: ',G%C%nq,G%C%nr,G%C%ns
      reported=.true.
    end if
    handled=.true.
  end subroutine try_traditional_boundary_rhs

  subroutine boundary_rhs_kernel(field,rate,mat,jac,mx,my,mz,n1,n2,n3,nmat,nmet,nx,ny,nz,x0,y0,z0,hx,hy,hz)
    integer,intent(in) :: n1,n2,n3,nmat,nmet,nx,ny,nz,x0,y0,z0
    real(wp),intent(in) :: field(n1,n2,n3,9),mat(n1,n2,n3,nmat),jac(n1,n2,n3)
    real(wp),intent(in) :: mx(n1,n2,n3,nmet),my(n1,n2,n3,nmet),mz(n1,n2,n3,nmet)
    real(wp),intent(inout) :: rate(n1,n2,n3,9)
    real(wp),intent(in) :: hx,hy,hz
    integer :: x,y,z,ix,iy,iz,s,c
    real(wp) :: ux(9),uy(9),uz(9),du(9),w,rhoj,l2m,lam,mu
    !$acc parallel loop gang vector collapse(3) present(field,rate,mat,jac,mx,my,mz) &
    !$acc& private(ix,iy,iz,s,c,ux,uy,uz,du,w,rhoj,l2m,lam,mu)
    do z=1,nz; do y=1,ny; do x=1,nx
      if (x>=7 .and. x<=nx-6 .and. y>=7 .and. y<=ny-6 .and. z>=7 .and. z<=nz-6) cycle
      ix=x0+x-1; iy=y0+y-1; iz=z0+z-1; ux=0.0_wp; uy=0.0_wp; uz=0.0_wp
      do s=1,nx
        w=sbp_weight(x,s,nx)/hx
        do c=1,3
          ux(c)=ux(c)+mx(ix,iy,iz,1)*w*field(x0+s-1,iy,iz,c)
          uy(c)=uy(c)+my(ix,iy,iz,1)*w*field(x0+s-1,iy,iz,c)
          uz(c)=uz(c)+mz(ix,iy,iz,1)*w*field(x0+s-1,iy,iz,c)
        end do
        do c=4,9
          ux(c)=ux(c)+w*field(x0+s-1,iy,iz,c)*jac(x0+s-1,iy,iz)*mx(x0+s-1,iy,iz,1)
          uy(c)=uy(c)+w*field(x0+s-1,iy,iz,c)*jac(x0+s-1,iy,iz)*my(x0+s-1,iy,iz,1)
          uz(c)=uz(c)+w*field(x0+s-1,iy,iz,c)*jac(x0+s-1,iy,iz)*mz(x0+s-1,iy,iz,1)
        end do
      end do
      do s=1,ny
        w=sbp_weight(y,s,ny)/hy
        do c=1,3
          ux(c)=ux(c)+mx(ix,iy,iz,2)*w*field(ix,y0+s-1,iz,c)
          uy(c)=uy(c)+my(ix,iy,iz,2)*w*field(ix,y0+s-1,iz,c)
          uz(c)=uz(c)+mz(ix,iy,iz,2)*w*field(ix,y0+s-1,iz,c)
        end do
        do c=4,9
          ux(c)=ux(c)+w*field(ix,y0+s-1,iz,c)*jac(ix,y0+s-1,iz)*mx(ix,y0+s-1,iz,2)
          uy(c)=uy(c)+w*field(ix,y0+s-1,iz,c)*jac(ix,y0+s-1,iz)*my(ix,y0+s-1,iz,2)
          uz(c)=uz(c)+w*field(ix,y0+s-1,iz,c)*jac(ix,y0+s-1,iz)*mz(ix,y0+s-1,iz,2)
        end do
      end do
      do s=1,nz
        w=sbp_weight(z,s,nz)/hz
        do c=1,3
          ux(c)=ux(c)+mx(ix,iy,iz,3)*w*field(ix,iy,z0+s-1,c)
          uy(c)=uy(c)+my(ix,iy,iz,3)*w*field(ix,iy,z0+s-1,c)
          uz(c)=uz(c)+mz(ix,iy,iz,3)*w*field(ix,iy,z0+s-1,c)
        end do
        do c=4,9
          ux(c)=ux(c)+w*field(ix,iy,z0+s-1,c)*jac(ix,iy,z0+s-1)*mx(ix,iy,z0+s-1,3)
          uy(c)=uy(c)+w*field(ix,iy,z0+s-1,c)*jac(ix,iy,z0+s-1)*my(ix,iy,z0+s-1,3)
          uz(c)=uz(c)+w*field(ix,iy,z0+s-1,c)*jac(ix,iy,z0+s-1)*mz(ix,iy,z0+s-1,3)
        end do
      end do
      rhoj=1.0_wp/(mat(ix,iy,iz,3)*jac(ix,iy,iz)); lam=mat(ix,iy,iz,1); mu=mat(ix,iy,iz,2); l2m=lam+2.0_wp*mu
      du(1)=(ux(4)+uy(7)+uz(8))*rhoj; du(2)=(ux(7)+uy(5)+uz(9))*rhoj; du(3)=(ux(8)+uy(9)+uz(6))*rhoj
      du(4)=l2m*ux(1)+lam*(uy(2)+uz(3)); du(5)=l2m*uy(2)+lam*(ux(1)+uz(3)); du(6)=l2m*uz(3)+lam*(ux(1)+uy(2))
      du(7)=mu*(uy(1)+ux(2)); du(8)=mu*(uz(1)+ux(3)); du(9)=mu*(uz(2)+uy(3))
      rate(ix,iy,iz,:)=rate(ix,iy,iz,:)+du
    end do; end do; end do
  end subroutine boundary_rhs_kernel

  !$acc routine seq
  real(wp) function sbp_weight(i,j,n) result(w)
    integer,intent(in) :: i,j,n
    integer :: ii,jj
    real(wp),parameter :: a(6,9)=reshape((/ &
      -1.582533518939116_wp,0.0_wp,0.071247104721830_wp,0.114713313798970_wp,-0.036210680656541_wp,-0.011398193015050_wp, &
       2.033378678700676_wp,-0.462059195631158_wp,-0.636451095137907_wp,-0.290087484386815_wp,0.105400944933782_wp,0.020437334208704_wp, &
      -0.141512858744873_wp,0.287258622978251_wp,0.0_wp,-0.306681191361148_wp,0.015764336127392_wp,0.011220896474665_wp, &
      -0.450398306578272_wp,0.258816087376832_wp,0.606235523609147_wp,0.0_wp,-0.707905442575989_wp,0.063183694641876_wp, &
       0.104488069284042_wp,-0.069112065532624_wp,-0.022902190275815_wp,0.520262285050482_wp,0.0_wp,-0.691649024426814_wp, &
       0.036577936277544_wp,-0.014903449191300_wp,-0.018129342917256_wp,-0.051642265516119_wp,0.769199413962647_wp,0.0_wp, &
       0.0_wp,0.0_wp,0.0_wp,0.013435342414630_wp,-0.164529643265203_wp,0.739709139060752_wp, &
       0.0_wp,0.0_wp,0.0_wp,0.0_wp,0.018281071473911_wp,-0.147941827812150_wp, &
       0.0_wp,0.0_wp,0.0_wp,0.0_wp,0.0_wp,0.016437980868017_wp /),(/6,9/))
    w=0.0_wp; ii=i; jj=j
    if (i>n-6) then; ii=n-i+1; jj=n-j+1; if (jj>=1 .and. jj<=9) w=-a(ii,jj); return; end if
    if (i<=6) then; if (j<=9) w=a(i,j); return; end if
    if (j==i-3) w=-1.0_wp/60.0_wp
    if (j==i-2) w=0.15_wp
    if (j==i-1) w=-0.75_wp
    if (j==i+1) w=0.75_wp
    if (j==i+2) w=-0.15_wp
    if (j==i+3) w=1.0_wp/60.0_wp
  end function sbp_weight

  logical function environment_true(name)
    character(len=*),intent(in) :: name
    character(len=16) :: value
    integer :: status
    call get_environment_variable(name,value,status=status)
    environment_true=status==0 .and. (trim(value)=='1' .or. trim(value)=='true' .or. trim(value)=='TRUE')
  end function environment_true
end module traditional_boundary_rhs_backend
