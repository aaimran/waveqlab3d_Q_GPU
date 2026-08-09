module traditional_boundary_backend
  use common, only : wp
  use datatypes, only : block_type, mms_type
  use openacc
  implicit none
  private
  public :: try_traditional_lx_boundary
  logical, save :: launch_reported = .false.
contains
  subroutine try_traditional_lx_boundary(B, mms_vars, handled)
    use mpi3dbasic, only : nprocs
    type(block_type), intent(inout) :: B
    type(mms_type), intent(in) :: mms_vars
    logical, intent(out) :: handled
    integer :: mx, px, my, mz, py, pz, ix, n1, n2, n3
    integer(kind=8) :: field_bytes, metric_bytes, material_bytes, face_bytes, work_bytes

    handled = .false.
    if (environment_true('WQL3D_PHASE6_DIAGNOSTICS') .and. .not.launch_reported) then
      write(*,'(A,I0,A,L1,A,A,A,I0,A,6(I0,1X),A,6(L1,1X))') &
           'Phase 6 Lx eligibility: ranks=',nprocs,' mms=',mms_vars%use_mms, &
           ' fd=',trim(B%fd_type),' order=',B%order,' bc=', &
           B%boundary_vars%Lx,B%boundary_vars%Rx,B%boundary_vars%Ly, &
           B%boundary_vars%Ry,B%boundary_vars%Lz,B%boundary_vars%Rz, &
           ' pml=',B%PMLB(:)%pml
    end if
    if (nprocs /= 1 .or. mms_vars%use_mms) return
    if (trim(B%fd_type) /= 'traditional' .or. B%order /= 6) return
    if (any(B%PMLB(:)%pml)) return
    if (B%boundary_vars%Lx <= 0 .and. B%boundary_vars%Rx <= 0) return
    if ((B%boundary_vars%Lx > 0 .and. (B%boundary_vars%Lx < 1 .or. B%boundary_vars%Lx > 3)) .or. &
        (B%boundary_vars%Rx > 0 .and. (B%boundary_vars%Rx < 1 .or. B%boundary_vars%Rx > 3))) return
    if (B%boundary_vars%Ly > 0 .or. B%boundary_vars%Ry > 0 .or. B%boundary_vars%Lz > 0 .or. &
        B%boundary_vars%Rz > 0) return
    if (.not.allocated(B%F%F) .or. .not.allocated(B%F%DF) .or. &
        .not.allocated(B%M%M) .or. .not.allocated(B%G%metricx) .or. &
        .not.allocated(B%work_boundary_q)) return
    if (size(B%F%F,4) /= 9 .or. size(B%F%DF,4) /= 9 .or. size(B%M%M,4) < 3) return
    mx = B%G%C%mq; px = B%G%C%pq; my = B%G%C%mr; mz = B%G%C%ms
    py = B%G%C%pr; pz = B%G%C%ps
    ix = mx-lbound(B%F%F,1)+1
    n1 = size(B%F%F,1); n2 = size(B%F%F,2); n3 = size(B%F%F,3)
    if (ix < 1 .or. ix > n1) return
    if (size(B%work_boundary_q,1) /= py-my+1 .or. &
        size(B%work_boundary_q,2) /= pz-mz+1 .or. &
        size(B%work_boundary_q,3) /= 9) return
    if (B%boundary_vars%Lx > 0 .and. (.not.allocated(B%B(1)%n_l) .or. &
        .not.allocated(B%B(1)%n_m) .or. .not.allocated(B%B(1)%n_n))) return
    if (B%boundary_vars%Rx > 0 .and. (.not.allocated(B%B(2)%n_l) .or. &
        .not.allocated(B%B(2)%n_m) .or. .not.allocated(B%B(2)%n_n))) return
    if (environment_true('WQL3D_PHASE6_DIAGNOSTICS') .and. .not.launch_reported) then
      write(*,'(A,3(I0,1X),A,3(I0,1X))') 'Phase 6 x-face shapes: work=', &
           shape(B%work_boundary_q),' field=',size(B%F%F,1),size(B%F%F,2),size(B%F%F,3)
    end if
    if (B%boundary_vars%Lx > 0 .and. (my-lbound(B%B(1)%n_l,1)+1 < 1 .or. &
        my-lbound(B%B(1)%n_l,1)+py-my+1 > size(B%B(1)%n_l,1) .or. &
        mz-lbound(B%B(1)%n_l,2)+1 < 1 .or. &
        mz-lbound(B%B(1)%n_l,2)+pz-mz+1 > size(B%B(1)%n_l,2))) return
    if (B%boundary_vars%Rx > 0 .and. (my-lbound(B%B(2)%n_l,1)+1 < 1 .or. &
        my-lbound(B%B(2)%n_l,1)+py-my+1 > size(B%B(2)%n_l,1) .or. &
        mz-lbound(B%B(2)%n_l,2)+1 < 1 .or. &
        mz-lbound(B%B(2)%n_l,2)+pz-mz+1 > size(B%B(2)%n_l,2))) return

    field_bytes = int(size(B%F%F),8)*int(storage_size(0.0_wp)/8,8)
    metric_bytes = int(size(B%G%metricx),8)*int(storage_size(0.0_wp)/8,8)
    material_bytes = int(size(B%M%M),8)*int(storage_size(0.0_wp)/8,8)
    work_bytes = int(size(B%work_boundary_q),8)*int(storage_size(0.0_wp)/8,8)
    if (.not.acc_is_present(B%F%F,field_bytes) .or. &
        .not.acc_is_present(B%F%DF,field_bytes) .or. &
        .not.acc_is_present(B%M%M,material_bytes) .or. &
        .not.acc_is_present(B%G%metricx,metric_bytes) .or. &
        .not.acc_is_present(B%work_boundary_q,work_bytes)) &
      error stop 'Phase 6 Lx boundary arrays are not present on device'

    !$acc update device(B%F%F,B%F%DF)
    if (B%boundary_vars%Lx > 0) then
      face_bytes = int(size(B%B(1)%n_l),8)*int(storage_size(0.0_wp)/8,8)
      if (.not.acc_is_present(B%B(1)%n_l,face_bytes) .or. &
          .not.acc_is_present(B%B(1)%n_m,face_bytes) .or. &
          .not.acc_is_present(B%B(1)%n_n,face_bytes)) error stop 'Phase 6 Lx normals absent'
      call x_boundary_kernel(B%F%F,B%F%DF,B%M%M,B%G%metricx, &
         B%B(1)%n_l,B%B(1)%n_m,B%B(1)%n_n,B%work_boundary_q, &
         n1,n2,n3,size(B%M%M,4),size(B%G%metricx,4), &
         size(B%B(1)%n_l,1),size(B%B(1)%n_l,2),py-my+1,pz-mz+1, &
         ix,my-lbound(B%F%F,2)+1,mz-lbound(B%F%F,3)+1, &
         my-lbound(B%B(1)%n_l,1)+1,mz-lbound(B%B(1)%n_l,2)+1, &
         B%boundary_vars%Lx,-1.0_wp,B%tau0/B%G%hq)
    end if
    if (B%boundary_vars%Rx > 0) then
      face_bytes = int(size(B%B(2)%n_l),8)*int(storage_size(0.0_wp)/8,8)
      if (.not.acc_is_present(B%B(2)%n_l,face_bytes) .or. &
          .not.acc_is_present(B%B(2)%n_m,face_bytes) .or. &
          .not.acc_is_present(B%B(2)%n_n,face_bytes)) error stop 'Phase 6 Rx normals absent'
      call x_boundary_kernel(B%F%F,B%F%DF,B%M%M,B%G%metricx, &
         B%B(2)%n_l,B%B(2)%n_m,B%B(2)%n_n,B%work_boundary_q, &
         n1,n2,n3,size(B%M%M,4),size(B%G%metricx,4), &
         size(B%B(2)%n_l,1),size(B%B(2)%n_l,2),py-my+1,pz-mz+1, &
         px-lbound(B%F%F,1)+1,my-lbound(B%F%F,2)+1,mz-lbound(B%F%F,3)+1, &
         my-lbound(B%B(2)%n_l,1)+1,mz-lbound(B%B(2)%n_l,2)+1, &
         B%boundary_vars%Rx,1.0_wp,B%tau0/B%G%hq)
    end if
    !$acc update self(B%F%DF,B%work_boundary_q)
    if (environment_true('WQL3D_PHASE6_DIAGNOSTICS') .and. .not.launch_reported) then
      write(*,'(A,I0,A,I0,A,2(I0,1X))') 'Phase 6 x-face launch: ny=',py-my+1, &
           ' nz=',pz-mz+1,' bc=',B%boundary_vars%Lx,B%boundary_vars%Rx
      launch_reported = .true.
    end if
    handled = .true.
  end subroutine try_traditional_lx_boundary

  subroutine x_boundary_kernel(field,rate,material,metricx,nl,nm,nn,work, &
       n1,n2,n3,nmat,nmetric,nly,nlz,ny,nz,ix,iy0,iz0,jy0,jz0,bc_type,side,penalty)
    integer,intent(in) :: n1,n2,n3,nmat,nmetric,nly,nlz,ny,nz
    integer,intent(in) :: ix,iy0,iz0,jy0,jz0,bc_type
    real(kind=wp),intent(in) :: field(n1,n2,n3,9),material(n1,n2,n3,nmat)
    real(kind=wp),intent(in) :: metricx(n1,n2,n3,nmetric)
    real(kind=wp),intent(in) :: nl(nly,nlz,3),nm(nly,nlz,3),nn(nly,nlz,3)
    real(kind=wp),intent(inout) :: rate(n1,n2,n3,9),work(ny,nz,9)
    real(kind=wp),intent(in) :: side,penalty
    integer :: iy,iz,j,k
    real(kind=wp) :: u(9),ubc(9),ux(9),l(3),m(3),nv(3),traction(3)
    real(kind=wp) :: rho,mu,lam,cp,cs,zp,zs,norm,r
    real(kind=wp) :: vl,vm,vn,tl,tm,tn,pl,pm,pn,ql,qm,qn
    real(kind=wp) :: fx,fy,fz,f_x,f_y,f_z
    !$acc parallel loop gang vector collapse(2) present(field,rate,material,metricx,nl,nm,nn,work) &
    !$acc& private(u,ubc,ux,l,m,nv,traction,rho,mu,lam,cp,cs,zp,zs,norm,r, &
    !$acc& vl,vm,vn,tl,tm,tn,pl,pm,pn,ql,qm,qn,fx,fy,fz,f_x,f_y,f_z,iy,iz)
    do k=1,nz
      do j=1,ny
        iy=iy0+j-1; iz=iz0+k-1
        u=field(ix,iy,iz,:); l=nl(jy0+j-1,jz0+k-1,:)
        m=nm(jy0+j-1,jz0+k-1,:); nv=nn(jy0+j-1,jz0+k-1,:)
        rho=material(ix,iy,iz,3); mu=material(ix,iy,iz,2); lam=material(ix,iy,iz,1)
        cp=sqrt((2.0_wp*mu+lam)/rho); cs=sqrt(mu/rho); zp=rho*cp; zs=rho*cs
        norm=sqrt(metricx(ix,iy,iz,1)**2+metricx(ix,iy,iz,2)**2+metricx(ix,iy,iz,3)**2)
        traction(1)=nv(1)*u(4)+nv(2)*u(7)+nv(3)*u(8)
        traction(2)=nv(1)*u(7)+nv(2)*u(5)+nv(3)*u(9)
        traction(3)=nv(1)*u(8)+nv(2)*u(9)+nv(3)*u(6)
        vl=dot_product(l,u(1:3)); vm=dot_product(m,u(1:3)); vn=dot_product(nv,u(1:3))
        tl=dot_product(l,traction); tm=dot_product(m,traction); tn=dot_product(nv,traction)
        if (bc_type == 1) then; r=0.0_wp; else if (bc_type == 2) then; r=1.0_wp; else; r=-1.0_wp; end if
        pl=0.5_wp*((1.0_wp-r)*zs*vl+side*(1.0_wp+r)*tl)
        pm=0.5_wp*((1.0_wp-r)*zs*vm+side*(1.0_wp+r)*tm)
        pn=0.5_wp*((1.0_wp-r)*zp*vn+side*(1.0_wp+r)*tn)
        ql=0.5_wp*((1.0_wp-r)*vl+side*(1.0_wp+r)/zs*tl)
        qm=0.5_wp*((1.0_wp-r)*vm+side*(1.0_wp+r)/zs*tm)
        qn=0.5_wp*((1.0_wp-r)*vn+side*(1.0_wp+r)/zp*tn)
        fx=l(1)*pl+m(1)*pm+nv(1)*pn; fy=l(2)*pl+m(2)*pm+nv(2)*pn; fz=l(3)*pl+m(3)*pm+nv(3)*pn
        f_x=l(1)*ql+m(1)*qm+nv(1)*qn; f_y=l(2)*ql+m(2)*qm+nv(2)*qn; f_z=l(3)*ql+m(3)*qm+nv(3)*qn
        ubc(1)=norm*fx; ubc(2)=norm*fy; ubc(3)=norm*fz
        ubc(4)=side*norm*nv(1)*f_x; ubc(5)=side*norm*nv(2)*f_y; ubc(6)=side*norm*nv(3)*f_z
        ubc(7)=side*norm*(nv(2)*f_x+nv(1)*f_y)
        ubc(8)=side*norm*(nv(3)*f_x+nv(1)*f_z)
        ubc(9)=side*norm*(nv(3)*f_y+nv(2)*f_z)
        work(j,k,:)=ubc
        ux(1:3)=ubc(1:3)/rho
        ux(4)=(2.0_wp*mu+lam)*ubc(4)+lam*(ubc(5)+ubc(6))
        ux(5)=(2.0_wp*mu+lam)*ubc(5)+lam*(ubc(4)+ubc(6))
        ux(6)=(2.0_wp*mu+lam)*ubc(6)+lam*(ubc(4)+ubc(5))
        ux(7:9)=mu*ubc(7:9)
        rate(ix,iy,iz,:)=rate(ix,iy,iz,:)-penalty*ux
      end do
    end do
  end subroutine x_boundary_kernel

  logical function environment_true(name)
    character(len=*),intent(in) :: name
    character(len=16) :: value
    integer :: status
    call get_environment_variable(name,value,status=status)
    environment_true=status==0 .and. (trim(value)=='1' .or. trim(value)=='true' .or. trim(value)=='TRUE')
  end function environment_true
end module traditional_boundary_backend
