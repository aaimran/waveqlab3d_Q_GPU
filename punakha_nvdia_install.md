# NVIDIA HPC SDK installation on Punakha without sudo

Date verified: 2026-08-06  
Host class: Punakha DGX H100  
GPU: NVIDIA H100 80 GB HBM3  
SDK: NVIDIA HPC SDK 26.5 with CUDA 13.2  
Install owner: `aimran`  
Install prefix: `/scratch/aimran/nvidia/hpc_sdk`

## 1. Background

Punakha did not provide an NVHPC environment module:

```bash
module spider nvhpc
module spider nvfortran
which nvfortran
```

Neither `nvhpc` nor `nvfortran` was found. The NVIDIA HPC SDK was therefore
installed in user-controlled scratch storage without `sudo`.

## 2. Download

```bash
mkdir -p /scratch/aimran/software/downloads
cd /scratch/aimran/software/downloads

wget \
  https://developer.download.nvidia.com/hpc-sdk/26.5/nvhpc_2026_265_Linux_x86_64_cuda_13.2.tar.gz
```

Downloaded archive:

```text
nvhpc_2026_265_Linux_x86_64_cuda_13.2.tar.gz
6,851,790,769 bytes, approximately 6.4 GiB
```

Check and extract it:

```bash
tar -tzf nvhpc_2026_265_Linux_x86_64_cuda_13.2.tar.gz >/dev/null
tar xpzf nvhpc_2026_265_Linux_x86_64_cuda_13.2.tar.gz
```

## 3. Installation mode

The initial interactive installation used option `3`, Auto install:

```bash
cd nvhpc_2026_265_Linux_x86_64_cuda_13.2
./install
```

Installation prefix:

```text
/scratch/aimran/nvidia/hpc_sdk
```

Although installation completed, first compiler use attempted to create:

```text
/home/aimran/.config/NVIDIA/nvhpc/26.5
```

That failed because the home filesystem quota was exceeded. Redirecting normal
cache variables was insufficient because this Auto-install configuration used
the home configuration location.

The verified solution was to rerun the installer as a Single-system install on
the H100 node. This stores the compiler configuration in the installation
tree:

```bash
cd /scratch/aimran/software/downloads/nvhpc_2026_265_Linux_x86_64_cuda_13.2

export NVHPC_SILENT=true
export NVHPC_INSTALL_DIR=/scratch/aimran/nvidia/hpc_sdk
export NVHPC_INSTALL_TYPE=single

./install
```

No existing SDK directory had to be deleted. The second installation refreshed
the same prefix and generated a usable local configuration.

For this account and cluster, use `single`, not `auto`, unless sufficient home
quota is restored.

## 4. Runtime environment

Apply these settings in every compilation or batch-job shell:

```bash
export NVHPC=/scratch/aimran/nvidia/hpc_sdk
export NVHPC_SDK_ROOT="$NVHPC/Linux_x86_64/26.5"

export PATH="$NVHPC_SDK_ROOT/compilers/bin:$NVHPC_SDK_ROOT/comm_libs/mpi/bin:$PATH"
export MANPATH="$NVHPC_SDK_ROOT/compilers/man:${MANPATH:-}"
export LD_LIBRARY_PATH="$NVHPC_SDK_ROOT/compilers/lib:$NVHPC_SDK_ROOT/comm_libs/mpi/lib:${LD_LIBRARY_PATH:-}"
export TMPDIR=/scratch/aimran/tmp
```

Create the scratch temporary directory once:

```bash
mkdir -p /scratch/aimran/tmp
```

These exports can be saved as:

```text
/scratch/aimran/software/nvhpc-env.sh
```

and loaded with:

```bash
source /scratch/aimran/software/nvhpc-env.sh
```

The installer also generated modulefiles under:

```text
/scratch/aimran/nvidia/hpc_sdk/modulefiles/nvhpc/26.5
```

The explicit environment above is retained as the reproducible baseline.

## 5. Compiler and MPI verification

Commands:

```bash
nvfortran --version
nvc --version
mpifort --show
```

Verified compiler output:

```text
nvfortran 26.5-0 64-bit target on x86-64 Linux -tp sapphirerapids
nvc 26.5-0 64-bit target on x86-64 Linux -tp sapphirerapids
```

The selected MPI wrapper is:

```text
/scratch/aimran/nvidia/hpc_sdk/Linux_x86_64/26.5/comm_libs/mpi/bin/mpifort
```

`mpifort --show` invokes `nvfortran` and links NVHPC's bundled HPC-X/Open MPI
5 libraries under `comm_libs/13.2/hpcx/hpcx-2.50/ompi5`. This is the correct
compiler/MPI pairing for the initial OpenACC build.

## 6. H100 OpenACC verification

Create and compile a minimal device query inside an H100 allocation:

```bash
mkdir -p /scratch/aimran/tmp/nvhpc-check
cd /scratch/aimran/tmp/nvhpc-check

printf '%s\n' \
  'program check' \
  '  use openacc' \
  '  print *, "OpenACC devices:", acc_get_num_devices(acc_device_nvidia)' \
  'end program check' > check.f90

nvfortran -acc=gpu -gpu=cc90 check.f90 -o check
./check
```

Verified result:

```text
OpenACC devices: 1
```

This confirms that:

- `nvfortran` runs correctly;
- OpenACC programs compile for H100 compute capability 9.0;
- the OpenACC runtime sees the allocated H100;
- the no-sudo SDK installation is operational.

It does not yet prove that MPI device-buffer communication is CUDA-aware.
CUDA-aware MPI must be tested separately before enabling it in WaveQLab3D-Q.

## 7. Next WaveQLab3D-Q step

```bash
source /scratch/aimran/software/nvhpc-env.sh
module load cmake/4.1.2

cd /scratch/aimran/waveqlab3d_Q_GPU

cmake --preset gpu-h100
cmake --build --preset gpu-h100 --parallel 8

ctest --test-dir build/gpu-h100 \
  -R fq8_effective_response_unit \
  --output-on-failure
```

Do not source Punakha's Intel compiler setup before configuring this build.
That environment can make CMake combine `nvfortran` with Intel MPI. The H100
preset pins `CMAKE_Fortran_COMPILER` to `nvfortran` and
`MPI_Fortran_COMPILER` to the NVHPC HPC-X `mpifort` wrapper. This avoids
legacy compiler-name logic mistaking an MPI wrapper for Intel Fortran while
still selecting the correct MPI libraries. After configuration, verify with:

```bash
grep -E 'CMAKE_Fortran_COMPILER:|MPI_Fortran_(COMPILER|LIBRARIES)' \
  build/gpu-h100/CMakeCache.txt
```

No selected MPI library should reside under `/opt/intel`.

The `gpu-h100` preset uses host-staged MPI intent. Do not enable the
`gpu-h100-cuda-aware-mpi` preset until the distributed correctness and direct
device-buffer communication gates have passed.
