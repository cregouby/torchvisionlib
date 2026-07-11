1#!/bin/bash
# Setup environment variables for torchvisionlib compilation
# Source this file before building: source setup_build_env.sh

# Get torch paths from R
TORCH_INCLUDE_PATH=$(Rscript -e "cat(system.file('include/torch/csrc/api/include', package = 'torch'))" | tail -n1)
TORCH_LIB_PATH=$(Rscript -e "cat(system.file('lib', package = 'torch'))" | tail -n1)

# Verify torch paths
if [ ! -f "$TORCH_INCLUDE_PATH/torch/torch.h" ]; then
  echo "ERROR: Invalid TORCH_INCLUDE_PATH: $TORCH_INCLUDE_PATH"
  return 1
fi

echo "TORCH_INCLUDE_PATH: $TORCH_INCLUDE_PATH"
echo "TORCH_LIB_PATH: $TORCH_LIB_PATH"

# Set C++ standard
export CXX_STD="CXX20"

# Platform-specific settings
if [[ "$(uname)" == "Darwin" ]]; then
  # macOS
  export PKG_LIBS="-L\"$TORCH_LIB_PATH\" -ltorch_cpu -ltorch -lc10 -Wl,-rpath,'@loader_path/../../torch/lib' -Wl,-rpath,'$TORCH_LIB_PATH'"
else
  # Linux
  export PKG_LIBS="-L\"$TORCH_LIB_PATH\" -ltorch_cpu -ltorch -lc10 -Wl,--no-as-needed,-rpath,'\$ORIGIN/../../torch/lib' -Wl,-rpath,'$TORCH_LIB_PATH'"
fi

# Base CPPFLAGS (append to existing if any)
export PKG_CPPFLAGS="${PKG_CPPFLAGS} -I../csrc/include/ -I\"$TORCH_INCLUDE_PATH\""

# CUDA support (optional)
if [ -n "$CUDA_HOME" ]; then
  echo "WITH_CUDA: 1 (CUDA_HOME=$CUDA_HOME)"
  export PKG_CPPFLAGS="${PKG_CPPFLAGS} -I\"$CUDA_HOME/include\" -DWITH_CUDA"
  export PKG_LIBS="${PKG_LIBS} -L\"$CUDA_HOME/lib64\" -lcudart"

  # NVCC settings for .cu files
  export NVCC="$CUDA_HOME/bin/nvcc"
  export NVCCFLAGS="-O3 -std=c++17 -Xcompiler -fPIC --expt-relaxed-constexpr"

  # Tell Make about CUDA objects
  export OBJECTS="cuda/ms_deform_attn_cuda.o"
else
  echo "WITH_CUDA: 0 (CUDA_HOME not set)"
fi

echo ""
echo "Locating libtorchvision..."

# Priority order: inst/libs > src > cache
TORCHVISION_LIB_PATH=""
PKG_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ -f "${PKG_ROOT}/inst/libs/libtorchvision.so" ]]; then
    TORCHVISION_LIB_PATH="${PKG_ROOT}/inst/libs"
    echo "    ✓ Found libtorchvision in inst/libs/"
elif [[ -f "${PKG_ROOT}/src/libtorchvision.so" ]]; then
    TORCHVISION_LIB_PATH="${PKG_ROOT}/src"
    echo "    ✓ Found libtorchvision in src/ (will copy to inst/libs during configure)"
elif [[ -f "${TORCHVISION_CACHE}/build/lib/libtorchvision.so" ]]; then
    TORCHVISION_LIB_PATH="${TORCHVISION_CACHE}/build/lib"
    echo "    ✓ Found libtorchvision in cache/"
else
    echo "    ⚠ WARNING: libtorchvision.so not found anywhere"
    echo "      Run: bash tools/build_libtorchvision_only.sh"
fi

# Export for child processes (Makevars, R scripts)
export TORCHVISION_LIB_PATH
echo "    TORCHVISION_LIB_PATH=${TORCHVISION_LIB_PATH:-<not set>}"


echo ""
echo "Environment variables set successfully!"
echo "You can now build with: R CMD build . && R CMD INSTALL ."
echo "Or with devtools: Rscript -e 'devtools::install()'"
