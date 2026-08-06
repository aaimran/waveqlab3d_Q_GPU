module fields

  !> fields modules handles fields defined within blocks

  use common, only : wp
  use datatypes, only : block_type, block_fields
  use rk_vector_kernels, only : scale_rate_array, update_state_array
   use, intrinsic :: ieee_arithmetic
  implicit none

  !> first few indices are for spatial dimensions, last index is for field component

contains


  subroutine init_fields(F, C, physics)

!!! initialize fields in a block

    use mpi3dcomm

    implicit none

    type(block_fields),intent(out) :: F
    type(cartesian3d_t),intent(in) :: C
    character(*),intent(in) :: physics

!!! fields will be specific to block physics

    select case(physics)

    case default

       stop 'invalid block physics in init_fields'

    case('elastic')

       call allocate_array_body(F%F ,C,9, ghost_nodes=.true., Fval = 0.0_wp)
       call allocate_array_body(F%DF,C,9, ghost_nodes=.true., Fval = 1.0e40_wp)

    case('acoustic')

       call allocate_array_body(F%F , C, 4, ghost_nodes=.true.)
       call allocate_array_body(F%DF, C, 4, ghost_nodes=.true.)

    end select

  end subroutine init_fields


  subroutine scale_rates_interior(F,A)

!!! multiply rates by RK coefficient A

    implicit none

    type(block_type),intent(inout) :: F
    real(kind = wp),intent(in) :: A
    

    call scale_rate_array(F%F%DF, A)
      if (F%M%anelastic) then
         call scale_rate_array(F%M%Deta4, A)
         call scale_rate_array(F%M%Deta5, A)
         call scale_rate_array(F%M%Deta6, A)
         call scale_rate_array(F%M%Deta7, A)
         call scale_rate_array(F%M%Deta8, A)
         call scale_rate_array(F%M%Deta9, A)
      end if
      if (F%M%anelastic_Q) then
         call scale_rate_array(F%M%Deta4Q, A)
         call scale_rate_array(F%M%Deta5Q, A)
         call scale_rate_array(F%M%Deta6Q, A)
         call scale_rate_array(F%M%Deta7Q, A)
         call scale_rate_array(F%M%Deta8Q, A)
         call scale_rate_array(F%M%Deta9Q, A)
      end if
      if (F%M%anelastic_Q8) then
         call scale_rate_array(F%M%Deta4Q8, A)
         call scale_rate_array(F%M%Deta5Q8, A)
         call scale_rate_array(F%M%Deta6Q8, A)
         call scale_rate_array(F%M%Deta7Q8, A)
         call scale_rate_array(F%M%Deta8Q8, A)
         call scale_rate_array(F%M%Deta9Q8, A)
      end if
      if (allocated(F%M%eta4Qf8)) then
         call scale_rate_array(F%M%Deta4Qf8, A)
         call scale_rate_array(F%M%Deta5Qf8, A)
         call scale_rate_array(F%M%Deta6Qf8, A)
         call scale_rate_array(F%M%Deta7Qf8, A)
         call scale_rate_array(F%M%Deta8Qf8, A)
         call scale_rate_array(F%M%Deta9Qf8, A)
      else if (F%M%anelastic_Qf) then
         call scale_rate_array(F%M%Deta4Qf, A)
         call scale_rate_array(F%M%Deta5Qf, A)
         call scale_rate_array(F%M%Deta6Qf, A)
         call scale_rate_array(F%M%Deta7Qf, A)
         call scale_rate_array(F%M%Deta8Qf, A)
         call scale_rate_array(F%M%Deta9Qf, A)
      end if
      if (allocated(F%M%eta4_8M)) then
         call scale_rate_array(F%M%Deta4_8M, A)
         call scale_rate_array(F%M%Deta5_8M, A)
         call scale_rate_array(F%M%Deta6_8M, A)
         call scale_rate_array(F%M%Deta7_8M, A)
         call scale_rate_array(F%M%Deta8_8M, A)
         call scale_rate_array(F%M%Deta9_8M, A)
      else if (F%M%anelastic_const_Q_4M) then
         call scale_rate_array(F%M%Deta4_4M, A)
         call scale_rate_array(F%M%Deta5_4M, A)
         call scale_rate_array(F%M%Deta6_4M, A)
         call scale_rate_array(F%M%Deta7_4M, A)
         call scale_rate_array(F%M%Deta8_4M, A)
         call scale_rate_array(F%M%Deta9_4M, A)
      end if

    if( F%PMLB(1)%pml .EQV. .TRUE.) then
       if(F%G%C%mq .le.  F%PMLB(1)%N_pml) then
          call scale_rate_array(F%PMLB(1)%DQ, A)
       end if
    end if

    
    if( F%PMLB(2)%pml .EQV. .TRUE.) then
        if(F%G%C%pq .ge. (F%G%C%nq- F%PMLB(2)%N_pml+1)) then
           call scale_rate_array(F%PMLB(2)%DQ, A)
        end if
     end if
     
     if( F%PMLB(3)%pml .EQV. .TRUE.) then
        if(F%G%C%mr .le. F%PMLB(3)%N_pml) then
           call scale_rate_array(F%PMLB(3)%DQ, A)
        end if
     end if
     
     if( F%PMLB(4)%pml .EQV. .TRUE.) then
         if(F%G%C%pr .ge. (F%G%C%nr- F%PMLB(4)%N_pml+1)) then
            call scale_rate_array(F%PMLB(4)%DQ, A)
         end if
     end if
     
     if( F%PMLB(5)%pml .EQV. .TRUE.) then
        if(F%G%C%ms .le.  F%PMLB(5)%N_pml) then
           call scale_rate_array(F%PMLB(5)%DQ, A)
        end if
     end if
     
     if( F%PMLB(6)%pml .EQV. .TRUE.) then
         if(F%G%C%ps .ge. (F%G%C%ns- F%PMLB(6)%N_pml+1)) then
            call scale_rate_array(F%PMLB(6)%DQ, A)
         end if
     end if
     

  end subroutine scale_rates_interior


  subroutine update_fields_interior(F,dt)

!!! update fields using rates

    implicit none

    type(block_type),intent(inout) :: F
    real(kind = wp),intent(in) :: dt

    call update_state_array(F%F%F, F%F%DF, dt)
      if (F%M%anelastic) then
         call update_state_array(F%M%eta4, F%M%Deta4, dt)
         call update_state_array(F%M%eta5, F%M%Deta5, dt)
         call update_state_array(F%M%eta6, F%M%Deta6, dt)
         call update_state_array(F%M%eta7, F%M%Deta7, dt)
         call update_state_array(F%M%eta8, F%M%Deta8, dt)
         call update_state_array(F%M%eta9, F%M%Deta9, dt)
      end if
      if (F%M%anelastic_Q) then
         call update_state_array(F%M%eta4Q, F%M%Deta4Q, dt)
         call update_state_array(F%M%eta5Q, F%M%Deta5Q, dt)
         call update_state_array(F%M%eta6Q, F%M%Deta6Q, dt)
         call update_state_array(F%M%eta7Q, F%M%Deta7Q, dt)
         call update_state_array(F%M%eta8Q, F%M%Deta8Q, dt)
         call update_state_array(F%M%eta9Q, F%M%Deta9Q, dt)
      end if
      if (F%M%anelastic_Q8) then
         call update_state_array(F%M%eta4Q8, F%M%Deta4Q8, dt)
         call update_state_array(F%M%eta5Q8, F%M%Deta5Q8, dt)
         call update_state_array(F%M%eta6Q8, F%M%Deta6Q8, dt)
         call update_state_array(F%M%eta7Q8, F%M%Deta7Q8, dt)
         call update_state_array(F%M%eta8Q8, F%M%Deta8Q8, dt)
         call update_state_array(F%M%eta9Q8, F%M%Deta9Q8, dt)
      end if
      if (allocated(F%M%eta4Qf8)) then
         call update_state_array(F%M%eta4Qf8, F%M%Deta4Qf8, dt)
         call update_state_array(F%M%eta5Qf8, F%M%Deta5Qf8, dt)
         call update_state_array(F%M%eta6Qf8, F%M%Deta6Qf8, dt)
         call update_state_array(F%M%eta7Qf8, F%M%Deta7Qf8, dt)
         call update_state_array(F%M%eta8Qf8, F%M%Deta8Qf8, dt)
         call update_state_array(F%M%eta9Qf8, F%M%Deta9Qf8, dt)
      else if (F%M%anelastic_Qf) then
         call update_state_array(F%M%eta4Qf, F%M%Deta4Qf, dt)
         call update_state_array(F%M%eta5Qf, F%M%Deta5Qf, dt)
         call update_state_array(F%M%eta6Qf, F%M%Deta6Qf, dt)
         call update_state_array(F%M%eta7Qf, F%M%Deta7Qf, dt)
         call update_state_array(F%M%eta8Qf, F%M%Deta8Qf, dt)
         call update_state_array(F%M%eta9Qf, F%M%Deta9Qf, dt)
      end if
      if (allocated(F%M%eta4_8M)) then
         call update_state_array(F%M%eta4_8M, F%M%Deta4_8M, dt)
         call update_state_array(F%M%eta5_8M, F%M%Deta5_8M, dt)
         call update_state_array(F%M%eta6_8M, F%M%Deta6_8M, dt)
         call update_state_array(F%M%eta7_8M, F%M%Deta7_8M, dt)
         call update_state_array(F%M%eta8_8M, F%M%Deta8_8M, dt)
         call update_state_array(F%M%eta9_8M, F%M%Deta9_8M, dt)
      else if (F%M%anelastic_const_Q_4M) then
         call update_state_array(F%M%eta4_4M, F%M%Deta4_4M, dt)
         call update_state_array(F%M%eta5_4M, F%M%Deta5_4M, dt)
         call update_state_array(F%M%eta6_4M, F%M%Deta6_4M, dt)
         call update_state_array(F%M%eta7_4M, F%M%Deta7_4M, dt)
         call update_state_array(F%M%eta8_4M, F%M%Deta8_4M, dt)
         call update_state_array(F%M%eta9_4M, F%M%Deta9_4M, dt)
      end if

    if( F%PMLB(1)%pml .EQV. .TRUE.) then
       if(F%G%C%mq .le. F%PMLB(1)%N_pml) then
         call update_state_array(F%PMLB(1)%Q, F%PMLB(1)%DQ, dt)
       end if
    end if

    
    if( F%PMLB(2)%pml .EQV. .TRUE.) then
        if(F%G%C%pq .ge. (F%G%C%nq- F%PMLB(2)%N_pml+1)) then
          call update_state_array(F%PMLB(2)%Q, F%PMLB(2)%DQ, dt)
        end if
     end if
     
     if( F%PMLB(3)%pml .EQV. .TRUE.) then
        if(F%G%C%mr .le.  F%PMLB(3)%N_pml) then
           call update_state_array(F%PMLB(3)%Q, F%PMLB(3)%DQ, dt)
        end if
     end if
     
     if( F%PMLB(4)%pml .EQV. .TRUE.) then
         if(F%G%C%pr .ge. (F%G%C%nr- F%PMLB(4)%N_pml+1)) then
            call update_state_array(F%PMLB(4)%Q, F%PMLB(4)%DQ, dt)
         end if
     end if
     
     if( F%PMLB(5)%pml .EQV. .TRUE.) then
        if(F%G%C%ms .le.  F%PMLB(5)%N_pml) then
           call update_state_array(F%PMLB(5)%Q, F%PMLB(5)%DQ, dt)
        end if
     end if
     
     if( F%PMLB(6)%pml .EQV. .TRUE.) then
         if(F%G%C%ps .ge. (F%G%C%ns- F%PMLB(6)%N_pml+1)) then
            call update_state_array(F%PMLB(6)%Q, F%PMLB(6)%DQ, dt)
         end if
     end if

     
         

  end subroutine update_fields_interior


  subroutine check_block_fields_for_invalid_values(F)

    implicit none

    type(block_type), intent(in) :: F

    if (allocated(F%F%F)) call check_real_4d(F%F%F, 'F%F', F%id)
    if (allocated(F%F%DF)) call check_real_4d(F%F%DF, 'F%DF', F%id)

  end subroutine check_block_fields_for_invalid_values


  subroutine check_real_4d(arr, label, block_id)

    implicit none

    real(kind = wp), intent(in) :: arr(:,:,:,:)
    character(*), intent(in) :: label
    integer, intent(in) :: block_id

    integer :: i, j, k, l

    do l = lbound(arr, 4), ubound(arr, 4)
       do k = lbound(arr, 3), ubound(arr, 3)
          do j = lbound(arr, 2), ubound(arr, 2)
             do i = lbound(arr, 1), ubound(arr, 1)
                if (.not. ieee_is_finite(arr(i,j,k,l))) then
                   write(*,'(A,I0,2X,A,2X,A,4(I0,1X),2X,A,ES12.4)') &
                        'ERROR: non-finite value in block', block_id, trim(label), &
                        '(i,j,k,l)=', i, j, k, l, 'value=', arr(i,j,k,l)
                   stop 'check_block_fields_for_invalid_values'
                end if
             end do
          end do
       end do
    end do

  end subroutine check_real_4d


  subroutine exchange_all_fields(F, C)

    use mpi3dcomm
    use mpi3dbasic, only: rank

    implicit none

    type(block_fields), intent(inout) :: F
    type(cartesian3d_t),intent(in) :: C
    integer :: i

    do i = 1, size(F%F, 4)
       call exchange_all_neighbors(C, F%F(:,:,:,i))
    end do

  end subroutine exchange_all_fields
!!! note that there is no set_rates_interior routine in this module;
!!! such a routine, which is quite involved, is stored separately in other modules,
!!! like elastic in elastic.f90, with one for each physics

  subroutine norm_fields(F,mx,my,mz,px, py, pz, n,sum)

    implicit none

    integer, intent(in) :: mx, my, mz, px, py, pz, n
    real(kind = wp), dimension(:,:,:,:), allocatable, intent(in) :: F
    real(kind = wp), intent(inout) :: sum

    integer :: i,j,k,l

    sum = 0.0_wp

    do l = 1,n
       do k = mz, pz
          do j = my, py
             do i = mx, px
                sum = sum + F(i,j,k,l)**2
             end do
          end do
       end do
    end do

    sum = sqrt(sum)

  end subroutine norm_fields


end module fields
