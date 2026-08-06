# Local NVHPC installation on Punakha

This procedure installs NVIDIA HPC SDK under `/work/$USER`; it does not need
root access and does not alter system modules.

## 1. Obtain the archive

From NVIDIA's HPC SDK download page, select the current **Linux x86-64 tar-file
installer**. Prefer the CUDA version bundled with the SDK rather than assuming
that the CUDA version printed by `nvidia-smi` is an installed toolkit.

Place the downloaded archive in a persistent location such as:

```bash
mkdir -p /work/$USER/software/downloads
cd /work/$USER/software/downloads
# Download or transfer the official nvhpc Linux x86-64 .tar.gz here.
```

Check space and archive integrity before installation:

```bash
df -h /work/$USER /tmp
tar -tzf nvhpc_*_Linux_x86_64*.tar.gz >/dev/null
```

## 2. Install without sudo

```bash
cd /scratch/$USER/waveqlab3d_Q_GPU
chmod u+x scripts/install_nvhpc_user.sh

scripts/install_nvhpc_user.sh \
  /work/$USER/software/downloads/nvhpc_*_Linux_x86_64*.tar.gz \
  | tee /work/$USER/software/nvhpc-install.log
```

The script prints version-specific environment exports. Save those exports in
`/work/$USER/software/nvhpc-env.sh`, or apply them in the current shell. Do not
add them globally until the compiler and MPI wrapper have been tested.

## 3. Validate the toolchain

After applying the printed environment:

```bash
which nvfortran
nvfortran --version
which mpifort
mpifort --show
nvidia-smi
```

`mpifort --show` must resolve to `nvfortran`, not Intel or GNU Fortran. If it
does not, the PATH ordering is wrong or the bundled MPI was not installed.

Compile a minimal OpenACC device check:

```bash
work=/tmp/$USER-nvhpc-check
mkdir -p "$work"
cd "$work"

printf '%s\n' \
  'program check' \
  '  use openacc' \
  '  print *, "OpenACC devices:", acc_get_num_devices(acc_device_nvidia)' \
  'end program check' > check.f90

nvfortran -acc=gpu -gpu=cc90 check.f90 -o check
./check
```

The program should report at least one NVIDIA device when executed inside an
H100 allocation.

## 4. Build WaveQLab3D-Q

```bash
cd /scratch/$USER/waveqlab3d_Q_GPU
module load cmake/4.1.2

cmake --preset gpu-h100
cmake --build --preset gpu-h100 --parallel 8

ctest --test-dir build/gpu-h100 \
  -R fq8_effective_response_unit \
  --output-on-failure
```

The current migration phase is a compiler baseline: the application can be
compiled with OpenACC, but numerical kernels have not yet been offloaded.

## 5. Important MPI restriction

Do not enable the `gpu-h100-cuda-aware-mpi` preset yet. The bundled MPI must be
tested separately for device-buffer transfers, and the solver must first pass
the planned host-staged multi-GPU correctness phase.

