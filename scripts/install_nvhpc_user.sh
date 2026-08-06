#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 /path/to/nvhpc_Linux_x86_64.tar.gz" >&2
  echo "Optional: NVHPC_USER_ROOT=/work/USER/nvidia/hpc_sdk" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

archive=$1
if [[ ! -f "$archive" ]]; then
  echo "error: NVHPC archive not found: $archive" >&2
  exit 2
fi

case "$archive" in
  *.tar.gz|*.tgz) ;;
  *) echo "error: expected a .tar.gz or .tgz archive" >&2; exit 2 ;;
esac

install_root=${NVHPC_USER_ROOT:-/work/${USER}/nvidia/hpc_sdk}
mkdir -p "$install_root"

work_root=${TMPDIR:-/tmp}
extract_dir=$(mktemp -d "${work_root%/}/nvhpc-install.XXXXXXXX")
cleanup() {
  rm -rf -- "$extract_dir"
}
trap cleanup EXIT

echo "Archive:      $archive"
echo "Install root: $install_root"
echo "Extracting installer..."
tar -xzf "$archive" -C "$extract_dir"

installer=$(find "$extract_dir" -maxdepth 3 -type f -name install -print -quit)
if [[ -z "$installer" ]]; then
  echo "error: no NVHPC install program found in archive" >&2
  exit 1
fi
chmod u+x "$installer"

echo "Running user-space NVHPC installer..."
NVHPC_SILENT=true \
NVHPC_INSTALL_DIR="$install_root" \
NVHPC_INSTALL_TYPE=single \
  "$installer"

nvfortran_path=$(find "$install_root/Linux_x86_64" -type f \
  -path '*/compilers/bin/nvfortran' -print 2>/dev/null | sort -V | tail -n 1)
if [[ -z "$nvfortran_path" || ! -x "$nvfortran_path" ]]; then
  echo "error: installation finished but nvfortran was not found" >&2
  exit 1
fi

sdk_root=${nvfortran_path%/compilers/bin/nvfortran}

echo
echo "NVHPC installation completed. Add these lines to the job environment:"
echo
printf 'export NVHPC=%q\n' "$install_root"
printf 'export NVHPC_SDK_ROOT=%q\n' "$sdk_root"
echo 'export PATH="$NVHPC_SDK_ROOT/compilers/bin:$NVHPC_SDK_ROOT/comm_libs/mpi/bin:$PATH"'
echo 'export MANPATH="$NVHPC_SDK_ROOT/compilers/man:${MANPATH:-}"'
echo 'export LD_LIBRARY_PATH="$NVHPC_SDK_ROOT/compilers/lib:$NVHPC_SDK_ROOT/comm_libs/mpi/lib:${LD_LIBRARY_PATH:-}"'
echo
echo "Detected compiler: $nvfortran_path"
"$nvfortran_path" --version | head -n 4

