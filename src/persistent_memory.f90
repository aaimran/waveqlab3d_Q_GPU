module persistent_memory

  use common, only : wp
  use datatypes, only : domain_type
  implicit none
  private
  public :: persistent_memory_bytes

  interface bytes
     module procedure bytes_real_1, bytes_real_2, bytes_real_3, bytes_real_4
     module procedure bytes_integer_1, bytes_character_1
  end interface bytes

contains

  integer(kind=8) function bytes_real_1(value)
    real(wp), allocatable, intent(in) :: value(:)
    bytes_real_1 = 0_8
    if (allocated(value)) bytes_real_1 = int(size(value),8)*int(storage_size(0.0_wp)/8,8)
  end function
  integer(kind=8) function bytes_real_2(value)
    real(wp), allocatable, intent(in) :: value(:,:)
    bytes_real_2 = 0_8
    if (allocated(value)) bytes_real_2 = int(size(value),8)*int(storage_size(0.0_wp)/8,8)
  end function
  integer(kind=8) function bytes_real_3(value)
    real(wp), allocatable, intent(in) :: value(:,:,:)
    bytes_real_3 = 0_8
    if (allocated(value)) bytes_real_3 = int(size(value),8)*int(storage_size(0.0_wp)/8,8)
  end function
  integer(kind=8) function bytes_real_4(value)
    real(wp), allocatable, intent(in) :: value(:,:,:,:)
    bytes_real_4 = 0_8
    if (allocated(value)) bytes_real_4 = int(size(value),8)*int(storage_size(0.0_wp)/8,8)
  end function
  integer(kind=8) function bytes_integer_1(value)
    integer, allocatable, intent(in) :: value(:)
    bytes_integer_1 = 0_8
    if (allocated(value)) bytes_integer_1 = int(size(value),8)*int(storage_size(0)/8,8)
  end function
  integer(kind=8) function bytes_character_1(value)
    character(len=64), allocatable, intent(in) :: value(:)
    bytes_character_1 = 0_8
    if (allocated(value)) bytes_character_1 = int(size(value),8)*64_8
  end function

  subroutine persistent_memory_bytes(D, category)
    type(domain_type), intent(in) :: D
    integer(kind=8), intent(out) :: category(7)
    integer :: i, j
    category = 0_8

    do i = 1, D%nblocks
       category(1) = category(1) + bytes(D%B(i)%G%x) + bytes(D%B(i)%G%metricx) + &
            bytes(D%B(i)%G%metricy) + bytes(D%B(i)%G%metricz) + bytes(D%B(i)%G%J)
       category(2) = category(2) + bytes(D%B(i)%M%M)
       call add_material_memory(D, i, category(2))
       category(3) = category(3) + bytes(D%B(i)%F%F) + bytes(D%B(i)%F%DF) + bytes(D%B(i)%P%P)
       do j = 1, 6
          category(4) = category(4) + bytes(D%B(i)%PMLB(j)%Q) + bytes(D%B(i)%PMLB(j)%DQ)
          category(5) = category(5) + bytes(D%B(i)%B(j)%X) + bytes(D%B(i)%B(j)%M) + &
               bytes(D%B(i)%B(j)%n_l) + bytes(D%B(i)%B(j)%n_m) + bytes(D%B(i)%B(j)%n_n) + &
               bytes(D%B(i)%B(j)%F) + bytes(D%B(i)%B(j)%DF) + bytes(D%B(i)%B(j)%Fopp) + &
               bytes(D%B(i)%B(j)%Mopp) + bytes(D%B(i)%B(j)%U) + bytes(D%B(i)%B(j)%DU)
       end do
       category(5) = category(5) + bytes(D%B(i)%work_boundary_q) + &
            bytes(D%B(i)%work_boundary_r) + bytes(D%B(i)%work_boundary_s)
       category(6) = category(6) + bytes(D%B(i)%MT%source_type) + bytes(D%B(i)%MT%mXX) + &
            bytes(D%B(i)%MT%mXY) + bytes(D%B(i)%MT%mXZ) + bytes(D%B(i)%MT%mYY) + &
            bytes(D%B(i)%MT%mYZ) + bytes(D%B(i)%MT%mZZ) + bytes(D%B(i)%MT%location_x) + &
            bytes(D%B(i)%MT%location_y) + bytes(D%B(i)%MT%location_z) + &
            bytes(D%B(i)%MT%near_x) + bytes(D%B(i)%MT%near_y) + bytes(D%B(i)%MT%near_z) + &
            bytes(D%B(i)%MT%alpha) + bytes(D%B(i)%MT%near_phys_x) + &
            bytes(D%B(i)%MT%near_phys_y) + bytes(D%B(i)%MT%near_phys_z) + &
            bytes(D%B(i)%MT%exact) + bytes(D%B(i)%MT%duration) + bytes(D%B(i)%MT%t_init)
    end do

    do i = 1, D%nifaces
       category(6) = category(6) + bytes(D%I(i)%V) + bytes(D%I(i)%DV) + bytes(D%I(i)%T) + &
            bytes(D%I(i)%S) + bytes(D%I(i)%DS) + bytes(D%I(i)%W) + bytes(D%I(i)%DW) + &
            bytes(D%I(i)%Svel) + bytes(D%I(i)%trup) + bytes(D%I(i)%work_F) + &
            bytes(D%I(i)%work_G) + bytes(D%I(i)%work_u_rotated) + &
            bytes(D%I(i)%work_v_rotated) + bytes(D%I(i)%work_u_hat) + bytes(D%I(i)%work_v_hat)
    end do

    category(7) = bytes(D%fault%time_rup) + bytes(D%fault%W) + bytes(D%fault%slip) + &
         bytes(D%fault%Svel) + bytes(D%fault%U_pluspres) + bytes(D%fault%V_pluspres) + &
         bytes(D%fault%Uhat_pluspres) + bytes(D%fault%Vhat_pluspres)
    do i = 1, D%nblocks
       category(7) = category(7) + bytes(D%seismometers(i)%i) + bytes(D%seismometers(i)%j) + &
            bytes(D%seismometers(i)%k) + bytes(D%seismometers(i)%file_unit) + &
            bytes(D%seismometers(i)%station_number) + bytes(D%seismometers(i)%i_phys) + &
            bytes(D%seismometers(i)%j_phys) + bytes(D%seismometers(i)%k_phys)
       if (allocated(D%plane_outputs(i)%P)) then
          do j = 1, size(D%plane_outputs(i)%P)
             category(7) = category(7) + bytes(D%plane_outputs(i)%P(j)%vx) + &
                  bytes(D%plane_outputs(i)%P(j)%vy) + bytes(D%plane_outputs(i)%P(j)%vz) + &
                  bytes(D%plane_outputs(i)%P(j)%vx_local) + &
                  bytes(D%plane_outputs(i)%P(j)%vy_local) + &
                  bytes(D%plane_outputs(i)%P(j)%vz_local) + &
                  bytes(D%plane_outputs(i)%P(j)%recv_work)
          end do
       end if
    end do
  end subroutine persistent_memory_bytes

  subroutine add_material_memory(D, i, total)
    type(domain_type), intent(in) :: D
    integer, intent(in) :: i
    integer(kind=8), intent(inout) :: total
    total = total + bytes(D%B(i)%M%Qp_inv) + bytes(D%B(i)%M%Qs_inv) + &
         bytes(D%B(i)%M%Qp_inv_Q) + bytes(D%B(i)%M%Qs_inv_Q) + &
         bytes(D%B(i)%M%Qp_inv_Q8) + bytes(D%B(i)%M%Qs_inv_Q8) + &
         bytes(D%B(i)%M%Qp_inv_Qf) + bytes(D%B(i)%M%Qs_inv_Qf) + &
         bytes(D%B(i)%M%Qp_inv_const_Q_4M) + bytes(D%B(i)%M%Qs_inv_const_Q_4M) + &
         bytes(D%B(i)%M%Qp_inv_const_Q_8M) + bytes(D%B(i)%M%Qs_inv_const_Q_8M) + &
         bytes(D%B(i)%M%Qp_inv_Qf8) + bytes(D%B(i)%M%Qs_inv_Qf8)
    call add_material_four_dimensional(D, i, total)
  end subroutine add_material_memory

  subroutine add_material_four_dimensional(D, i, total)
    type(domain_type), intent(in) :: D
    integer, intent(in) :: i
    integer(kind=8), intent(inout) :: total
    total = total + &
      bytes(D%B(i)%M%eta4)+bytes(D%B(i)%M%eta5)+bytes(D%B(i)%M%eta6)+bytes(D%B(i)%M%eta7)+bytes(D%B(i)%M%eta8)+bytes(D%B(i)%M%eta9)+ &
      bytes(D%B(i)%M%Deta4)+bytes(D%B(i)%M%Deta5)+bytes(D%B(i)%M%Deta6)+bytes(D%B(i)%M%Deta7)+bytes(D%B(i)%M%Deta8)+bytes(D%B(i)%M%Deta9)+ &
      bytes(D%B(i)%M%eta4Q)+bytes(D%B(i)%M%eta5Q)+bytes(D%B(i)%M%eta6Q)+bytes(D%B(i)%M%eta7Q)+bytes(D%B(i)%M%eta8Q)+bytes(D%B(i)%M%eta9Q)+ &
      bytes(D%B(i)%M%Deta4Q)+bytes(D%B(i)%M%Deta5Q)+bytes(D%B(i)%M%Deta6Q)+bytes(D%B(i)%M%Deta7Q)+bytes(D%B(i)%M%Deta8Q)+bytes(D%B(i)%M%Deta9Q)+ &
      bytes(D%B(i)%M%eta4Q8)+bytes(D%B(i)%M%eta5Q8)+bytes(D%B(i)%M%eta6Q8)+bytes(D%B(i)%M%eta7Q8)+bytes(D%B(i)%M%eta8Q8)+bytes(D%B(i)%M%eta9Q8)+ &
      bytes(D%B(i)%M%Deta4Q8)+bytes(D%B(i)%M%Deta5Q8)+bytes(D%B(i)%M%Deta6Q8)+bytes(D%B(i)%M%Deta7Q8)+bytes(D%B(i)%M%Deta8Q8)+bytes(D%B(i)%M%Deta9Q8)+ &
      bytes(D%B(i)%M%eta4Qf)+bytes(D%B(i)%M%eta5Qf)+bytes(D%B(i)%M%eta6Qf)+bytes(D%B(i)%M%eta7Qf)+bytes(D%B(i)%M%eta8Qf)+bytes(D%B(i)%M%eta9Qf)+ &
      bytes(D%B(i)%M%Deta4Qf)+bytes(D%B(i)%M%Deta5Qf)+bytes(D%B(i)%M%Deta6Qf)+bytes(D%B(i)%M%Deta7Qf)+bytes(D%B(i)%M%Deta8Qf)+bytes(D%B(i)%M%Deta9Qf)+ &
      bytes(D%B(i)%M%eta4_4M)+bytes(D%B(i)%M%eta5_4M)+bytes(D%B(i)%M%eta6_4M)+bytes(D%B(i)%M%eta7_4M)+bytes(D%B(i)%M%eta8_4M)+bytes(D%B(i)%M%eta9_4M)+ &
      bytes(D%B(i)%M%Deta4_4M)+bytes(D%B(i)%M%Deta5_4M)+bytes(D%B(i)%M%Deta6_4M)+bytes(D%B(i)%M%Deta7_4M)+bytes(D%B(i)%M%Deta8_4M)+bytes(D%B(i)%M%Deta9_4M)+ &
      bytes(D%B(i)%M%eta4_8M)+bytes(D%B(i)%M%eta5_8M)+bytes(D%B(i)%M%eta6_8M)+bytes(D%B(i)%M%eta7_8M)+bytes(D%B(i)%M%eta8_8M)+bytes(D%B(i)%M%eta9_8M)+ &
      bytes(D%B(i)%M%Deta4_8M)+bytes(D%B(i)%M%Deta5_8M)+bytes(D%B(i)%M%Deta6_8M)+bytes(D%B(i)%M%Deta7_8M)+bytes(D%B(i)%M%Deta8_8M)+bytes(D%B(i)%M%Deta9_8M)+ &
      bytes(D%B(i)%M%eta4Qf8)+bytes(D%B(i)%M%eta5Qf8)+bytes(D%B(i)%M%eta6Qf8)+bytes(D%B(i)%M%eta7Qf8)+bytes(D%B(i)%M%eta8Qf8)+bytes(D%B(i)%M%eta9Qf8)+ &
      bytes(D%B(i)%M%Deta4Qf8)+bytes(D%B(i)%M%Deta5Qf8)+bytes(D%B(i)%M%Deta6Qf8)+bytes(D%B(i)%M%Deta7Qf8)+bytes(D%B(i)%M%Deta8Qf8)+bytes(D%B(i)%M%Deta9Qf8)
  end subroutine add_material_four_dimensional

end module persistent_memory
