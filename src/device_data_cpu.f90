module device_data
  use datatypes, only : domain_type
  implicit none
  private
  public :: enter_domain_device_data, assert_domain_device_data_present, &
       update_domain_host_data, exit_domain_device_data
contains
  subroutine enter_domain_device_data(D)
    type(domain_type), intent(inout) :: D
    if (D%nblocks < 0) error stop 'invalid domain block count'
  end subroutine enter_domain_device_data

  subroutine assert_domain_device_data_present(D)
    type(domain_type), intent(inout) :: D
    if (D%nblocks < 0) error stop 'invalid domain block count'
  end subroutine assert_domain_device_data_present

  subroutine exit_domain_device_data(D)
    type(domain_type), intent(inout) :: D
    if (D%nblocks < 0) error stop 'invalid domain block count'
  end subroutine exit_domain_device_data

  subroutine update_domain_host_data(D)
    type(domain_type), intent(inout) :: D
    if (D%nblocks < 0) error stop 'invalid domain block count'
  end subroutine update_domain_host_data
end module device_data
