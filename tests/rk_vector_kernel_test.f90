program rk_vector_kernel_test
  use common, only : wp
  use rk_vector_kernels, only : scale_rate_array, update_state_array
  use rk_vector_test_data, only : enter_test_data, exit_test_data
  implicit none
  integer, parameter :: nq=7, nr=5, ns=3, nc=4
  real(kind=wp), allocatable :: state(:,:,:,:), rate(:,:,:,:)
  real(kind=wp), allocatable :: expected_state(:,:,:,:), expected_rate(:,:,:,:)
  real(kind=wp), parameter :: coefficient=-0.375_wp, increment=0.125_wp
  integer :: i, j, k, c
  real(kind=wp) :: rate_error, state_error, scale

  allocate(state(-2:nq-3,3:nr+2,-1:ns-2,nc), rate(-2:nq-3,3:nr+2,-1:ns-2,nc))
  allocate(expected_state, source=state)
  allocate(expected_rate, source=rate)
  do c=1,nc; do k=lbound(state,3),ubound(state,3)
    do j=lbound(state,2),ubound(state,2); do i=lbound(state,1),ubound(state,1)
      state(i,j,k,c) = real(11*i-7*j+5*k+3*c,wp)/13.0_wp
      rate(i,j,k,c) = real(-2*i+9*j-4*k+7*c,wp)/17.0_wp
    end do; end do
  end do; end do
  expected_rate = coefficient*rate
  expected_state = state + increment*expected_rate

  call enter_test_data(state,rate)
  call scale_rate_array(rate,coefficient)
  call update_state_array(state,rate,increment)
  rate_error = maxval(abs(rate-expected_rate))
  state_error = maxval(abs(state-expected_state))
  scale = max(1.0_wp, maxval(abs(expected_rate)), maxval(abs(expected_state)))
  write(*,'(A,ES12.4,A,ES12.4)') 'RK vector errors: rate=',rate_error,', state=',state_error
  write(*,'(A,4ES12.4)') 'RK rate ranges: actual min/max, expected min/max=', &
       minval(rate), maxval(rate), minval(expected_rate), maxval(expected_rate)
  if (rate_error > 32.0_wp*epsilon(1.0_wp)*scale) error stop 'RK rate scaling mismatch'
  if (state_error > 32.0_wp*epsilon(1.0_wp)*scale) error stop 'RK state update mismatch'
  call exit_test_data(state,rate)
  write(*,'(A)') 'PASS: asymmetric RK vector scale/update matches the CPU expression'
end program rk_vector_kernel_test
