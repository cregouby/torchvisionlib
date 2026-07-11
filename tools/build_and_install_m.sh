#!/usr/bin/env bash
# ----------------------------------------------------------------------
# tools/build_and_install.sh
#
#   * Keeps a persistent torchvision source tree in $HOME/.cache/torchvision
#   * Updates it with git pull
#   * Passes the path to CMake (USE_LOCAL_TORCHVISION=ON)
#   * Builds libtorchvision.so and torchvisionlib.so
#   * Moves libtorchvision.so to the directory that .onLoad() expects
#   * Patches the r‑path, regenerates Rcpp export, installs the R package
#   * Runs the test suite (including the ps_roi_align test)
#
#   The only change needed to avoid the “identical file” error is the
#   **mv**+guard block below.
# ----------------------------------------------------------------------
set -euo pipefail

# ----------------------------------------------------------------------
# 0️⃣  Paths
# ----------------------------------------------------------------------
PKG_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)   # package root
C_SRC="${PKG_ROOT}/csrc"
BUILD_DIR="${C_SRC}/build"
INST_DIR="${PKG_ROOT}/inst"
INST_LIBS="${INST_DIR}/libs"   # .onLoad() looks here

# ----------------------------------------------------------------------
# 1️⃣  Persistent torchvision cache
# ----------------------------------------------------------------------
TORCHVISION_CACHE="${HOME}/.cache/torchvision"
TORCHVISION_TAG="v0.22.1"   # must match the tag used by CMakeLists.txt

mkdir -p "${TORCHVISION_CACHE}"
if [[ -d "${TORCHVISION_CACHE}/.git" ]]; then
  echo "🗂  Using cached torchvision repo at ${TORCHVISION_CACHE}"
  # Fetch latest tags (--force allows updating existing tags if moved)
  git -C "${TORCHVISION_CACHE}" fetch --tags --force origin
  git -C "${TORCHVISION_CACHE}" checkout "${TORCHVISION_TAG}"
else
  echo "🛟  Cloning torchvision (${TORCHVISION_TAG}) into cache..."
  git clone --depth 1 --branch "${TORCHVISION_TAG}" \
            https://github.com/pytorch/vision "${TORCHVISION_CACHE}"
fi

# ----------------------------------------------------------------------
# 2️⃣  Torch installation path
# ----------------------------------------------------------------------
TORCH_PATH=$(Rscript -e "cat(torch::torch_install_path())")
echo "🔧 Using torch installation at: $TORCH_PATH"

# ----------------------------------------------------------------------
# 3️⃣  Check for ABI compatibility issues and select compiler
# ----------------------------------------------------------------------
MAKEVARS="${HOME}/.R/Makevars"
MAKEVARS_BACKUP="${MAKEVARS}.torchvisionlib_backup"
MAKEVARS_TEMP="${MAKEVARS}.torchvisionlib_temp"
RESTORE_MAKEVARS=false
declare -a CMAKE_COMPILER_ARGS=()

# Function to check if a compiler path is non-system
is_non_system_compiler() {
  local compiler="$1"
  if [[ "$compiler" =~ /opt/ ]] || \
     [[ "$compiler" =~ /usr/local/ ]] || \
     [[ "$compiler" =~ homebrew ]] || \
     [[ "$compiler" =~ Cellar ]]; then
    return 0  # true - it is non-system
  fi
  return 1  # false - it is system
}

if [[ -f "${MAKEVARS}" ]]; then
  echo "📄 Found Makevars at ${MAKEVARS}"

  # Extract CXX compiler (match CXX= or CXX1= etc, but not CXXFLAGS)
  CXX_COMPILER=$(grep -E "^CXX[0-9]*\s*=" "${MAKEVARS}" | head -1 | sed 's/^[^=]*=[[:space:]]*//' | awk '{print $1}' || true)
  # Extract CC compiler (match CC= but not CFLAGS or CXXFLAGS)
  CC_COMPILER=$(grep -E "^CC\s*=" "${MAKEVARS}" | head -1 | sed 's/^[^=]*=[[:space:]]*//' | awk '{print $1}' || true)

  # Check for non-system compiler that may cause ABI issues
  if [[ -n "${CXX_COMPILER}" ]] && is_non_system_compiler "${CXX_COMPILER}"; then
    echo "⚠️  WARNING: Non-system compiler detected in Makevars!"
    echo "   Compiler: ${CXX_COMPILER}"
    echo "   This may cause ABI incompatibility with torch (bus errors, segfaults)"
    echo ""
    echo "   torch is typically built with the system compiler (/usr/bin/clang++)"
    echo "   To avoid runtime crashes, we'll use the system compiler for this build."
    echo ""

    # Ask user what to do (or use environment variable to skip prompt)
    if [[ "${TORCHVISIONLIB_FORCE_SYSTEM_COMPILER:-yes}" == "yes" ]]; then
      echo "   → Using system compiler for compatibility"
      echo "   → Your Makevars will be temporarily moved aside during build"
      echo ""

      # Backup and temporarily disable Makevars
      cp "${MAKEVARS}" "${MAKEVARS_BACKUP}"
      mv "${MAKEVARS}" "${MAKEVARS_TEMP}"
      RESTORE_MAKEVARS=true

      echo "✅ Makevars backed up to: ${MAKEVARS_BACKUP}"
      echo "✅ Makevars temporarily moved to: ${MAKEVARS_TEMP}"
      echo ""
    else
      echo "   Using your Makevars compiler (set TORCHVISIONLIB_FORCE_SYSTEM_COMPILER=yes to override)"
      CMAKE_COMPILER_ARGS+=("-DCMAKE_CXX_COMPILER=${CXX_COMPILER}")
      if [[ -n "${CC_COMPILER}" ]]; then
        CMAKE_COMPILER_ARGS+=("-DCMAKE_C_COMPILER=${CC_COMPILER}")
      fi
    fi
  else
    # System compiler - use it
    if [[ -n "${CXX_COMPILER}" ]]; then
      echo "🔧 Using CXX compiler from Makevars: ${CXX_COMPILER}"
      CMAKE_COMPILER_ARGS+=("-DCMAKE_CXX_COMPILER=${CXX_COMPILER}")
    else
      echo "ℹ️  No CXX compiler in Makevars (using CMake default)"
    fi

    if [[ -n "${CC_COMPILER}" ]]; then
      echo "🔧 Using CC compiler from Makevars: ${CC_COMPILER}"
      CMAKE_COMPILER_ARGS+=("-DCMAKE_C_COMPILER=${CC_COMPILER}")
    else
      echo "ℹ️  No CC compiler in Makevars (using CMake default)"
    fi
  fi
else
  echo "ℹ️  No Makevars file found (using CMake defaults)"
fi

# ----------------------------------------------------------------------
# 3b️⃣  Detect torch's ABI and set compatible deployment target
# ----------------------------------------------------------------------
if [[ "$(uname)" == "Darwin" ]]; then
  echo "🔍 Detecting torch's libc++ ABI version..."

  # Find torch's libtorch_cpu library
  TORCH_CPU_LIB=$(Rscript -e "cat(file.path(system.file('lib', package='torch'), 'libtorch_cpu.dylib'))" 2>/dev/null || true)

  if [[ -f "${TORCH_CPU_LIB}" ]]; then
    # Extract libc++ version that torch was built with
    TORCH_LIBCXX=$(otool -L "${TORCH_CPU_LIB}" | grep "libc++.1.dylib" || true)

    if [[ -n "${TORCH_LIBCXX}" ]]; then
      echo "   torch's libc++ dependency: ${TORCH_LIBCXX}"

      # Extract current version number (e.g., 1700.255.5 or 2000.67.0)
      # Look for "current version X.Y.Z" specifically
      LIBCXX_VERSION=$(echo "${TORCH_LIBCXX}" | grep -oE "current version [0-9]+\.[0-9]+\.[0-9]+" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" || true)

      if [[ -n "${LIBCXX_VERSION}" ]]; then
        # Major version: 1700 -> macOS 13/14, 1800 -> macOS 14, 2000 -> macOS 15+
        LIBCXX_MAJOR=$(echo "${LIBCXX_VERSION}" | cut -d. -f1)

        echo "   libc++ version: ${LIBCXX_VERSION} (major: ${LIBCXX_MAJOR})"

        # Map libc++ version to macOS deployment target
        if [[ "${LIBCXX_MAJOR}" -lt 1800 ]]; then
          DEPLOYMENT_TARGET="13.0"
        elif [[ "${LIBCXX_MAJOR}" -lt 2000 ]]; then
          DEPLOYMENT_TARGET="14.0"
        else
          DEPLOYMENT_TARGET="15.0"
        fi

        echo "🎯 Setting deployment target to ${DEPLOYMENT_TARGET} for ABI compatibility"
        export MACOSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}"
        CMAKE_COMPILER_ARGS+=("-DCMAKE_OSX_DEPLOYMENT_TARGET=${DEPLOYMENT_TARGET}")

        # Try to find a compatible SDK
        # Prefer older SDKs for better compatibility
        for SDK_PATH in /Library/Developer/CommandLineTools/SDKs/MacOSX{15.4,15,26}.sdk; do
          if [[ -d "${SDK_PATH}" ]]; then
            echo "   Using SDK: ${SDK_PATH}"
            export SDKROOT="${SDK_PATH}"
            CMAKE_COMPILER_ARGS+=("-DCMAKE_OSX_SYSROOT=${SDK_PATH}")
            break
          fi
        done
      else
        echo "⚠️  Could not extract libc++ version from torch"
      fi
    else
      echo "⚠️  Could not find libc++ dependency in torch"
    fi
  else
    echo "⚠️  Could not find torch's libtorch_cpu.dylib at: ${TORCH_CPU_LIB}"
  fi
fi

# Cleanup function to restore Makevars
cleanup_makevars() {
  if [[ "${RESTORE_MAKEVARS}" == "true" ]] && [[ -f "${MAKEVARS_TEMP}" ]]; then
    echo ""
    echo "🔄 Restoring original Makevars..."
    mv "${MAKEVARS_TEMP}" "${MAKEVARS}"
    echo "✅ Makevars restored"
  fi
}

# Set trap to restore Makevars on exit (success or failure)
# Note: We'll manually call this AFTER R CMD INSTALL to ensure the R package
# is also built with the system compiler
trap cleanup_makevars EXIT ERR INT TERM

# ----------------------------------------------------------------------
# 4️⃣  Build with CMake (out‑of‑source)
# ----------------------------------------------------------------------
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

echo "🏗️  Running cmake..."
if [[ ${#CMAKE_COMPILER_ARGS[@]} -gt 0 ]]; then
  echo "   Using compiler args: ${CMAKE_COMPILER_ARGS[*]}"
  cmake .. \
        -DCMAKE_INSTALL_PREFIX="${INST_DIR}" \
        -DTORCH_HOME="${TORCH_PATH}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DUSE_LOCAL_TORCHVISION=ON \
        -DTORCHVISION_SOURCE_DIR="${TORCHVISION_CACHE}" \
        -DTORCHVISION_CMAKE_ARGS="-DCMAKE_PREFIX_PATH:PATH=${TORCH_PATH}" \
        "${CMAKE_COMPILER_ARGS[@]}"
else
  cmake .. \
        -DCMAKE_INSTALL_PREFIX="${INST_DIR}" \
        -DTORCH_HOME="${TORCH_PATH}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DUSE_LOCAL_TORCHVISION=ON \
        -DTORCHVISION_SOURCE_DIR="${TORCHVISION_CACHE}" \
        -DTORCHVISION_CMAKE_ARGS="-DCMAKE_PREFIX_PATH:PATH=${TORCH_PATH}"
fi

if [[ $? -ne 0 ]]; then
  echo "❌ CMake configuration failed!"
  exit 1
fi
echo "✅ CMake configuration succeeded"

# Detect number of cores (Linux vs macOS)
if command -v nproc >/dev/null 2>&1; then
  NCORES=$(nproc)
else
  NCORES=$(sysctl -n hw.ncpu)
fi
cmake --build . --target install -- -j${NCORES}

# ----------------------------------------------------------------------
# 5️⃣  Verify libtorchvision library was installed
# ----------------------------------------------------------------------
# Detect platform-specific library extension
if [[ "$(uname)" == "Linux" ]]; then
  LIB_EXT="so"
elif [[ "$(uname)" == "Darwin" ]]; then
  LIB_EXT="dylib"
else
  LIB_EXT="dll"
fi

# CMake already installs to inst/lib/ which is where .onLoad() expects it
TORCHVISION_LIB="${INST_DIR}/lib/libtorchvision.${LIB_EXT}"
if [[ ! -f "$TORCHVISION_LIB" ]]; then
  echo "ERROR: Expected ${TORCHVISION_LIB} does not exist after install."
  exit 1
fi

echo "✅ libtorchvision.${LIB_EXT} installed to ${INST_DIR}/lib/"

# ----------------------------------------------------------------------
# 6️⃣  Patch r‑path of the external library
# ----------------------------------------------------------------------
TORCH_LIB_PATH=$(Rscript -e "cat(system.file('lib', package = 'torch'))")
echo "🔗 Torch lib directory: $TORCH_LIB_PATH"

if [[ "$(uname)" == "Linux" ]]; then
  if ! command -v patchelf >/dev/null 2>&1; then
    echo "ERROR: patchelf not installed – sudo apt-get install patchelf"
    exit 1
  fi
  patchelf --set-rpath "$TORCH_LIB_PATH" "${TORCHVISION_LIB}"
  echo "🛠  Patched rpath with patchelf"
else
  # On macOS, add_rpath fails if the rpath already exists, so ignore errors
  install_name_tool -add_rpath "$TORCH_LIB_PATH" "${TORCHVISION_LIB}" 2>/dev/null || true
  echo "🛠  Patched rpath with install_name_tool"
fi

# ----------------------------------------------------------------------
# 7️⃣  Regenerate Rcpp export code
# ----------------------------------------------------------------------
Rscript -e "Rcpp::compileAttributes('${PKG_ROOT}')"
Rscript -e "torchexport::export('${PKG_ROOT}')"

# ----------------------------------------------------------------------
# 8️⃣  Install the R package
# ----------------------------------------------------------------------
echo "📦 Installing R package..."
if [[ "${RESTORE_MAKEVARS}" == "true" ]]; then
  echo "   (Using system compiler - Makevars temporarily disabled)"
  # Double-check Makevars is not present
  if [[ -f "${MAKEVARS}" ]]; then
    echo "⚠️  WARNING: Makevars exists but should have been moved!"
    ls -la "${MAKEVARS}"
  else
    echo "✅ Confirmed: ${MAKEVARS} is not present for R CMD INSTALL"
  fi

  # Check for other possible Makevars locations
  for possible_makevars in "${HOME}/.R/Makevars.site" "/Library/Frameworks/R.framework/Resources/etc/Makeconf"; do
    if [[ -f "${possible_makevars}" ]]; then
      echo "ℹ️  Note: Found ${possible_makevars}"
      if grep -q "llvm\|Cellar" "${possible_makevars}" 2>/dev/null; then
        echo "⚠️  WARNING: ${possible_makevars} contains LLVM references!"
      fi
    fi
  done
fi

# Clean old object files that may have been built with different deployment target
echo "🧹 Cleaning old object files..."
if [[ -d "${PKG_ROOT}/src" ]]; then
  rm -f "${PKG_ROOT}/src"/*.o "${PKG_ROOT}/src"/*.so 2>/dev/null || true
  echo "   Removed stale object files from src/"
fi

# Show what R will use for compilation
echo "🔍 R compiler configuration:"
Rscript -e "cat('CXX:', system2('R', c('CMD', 'config', 'CXX'), stdout = TRUE), '\n')"
if [[ -n "${SDKROOT:-}" ]]; then
  echo "   SDKROOT: ${SDKROOT}"
fi
if [[ -n "${MACOSX_DEPLOYMENT_TARGET:-}" ]]; then
  echo "   MACOSX_DEPLOYMENT_TARGET: ${MACOSX_DEPLOYMENT_TARGET}"
fi

# Install R package (SDKROOT and MACOSX_DEPLOYMENT_TARGET env vars will be inherited if set)
R CMD INSTALL "${PKG_ROOT}"
echo "📦 Package installed."

# Show what compiler was actually used
if [[ -f "${PKG_ROOT}/src/RcppExports.o" ]]; then
  echo "🔍 Checking compiled object..."
  if command -v otool >/dev/null 2>&1; then
    otool -L "${PKG_ROOT}/src/RcppExports.o" 2>/dev/null || echo "   (object file inspection not available)"
  fi
fi

# ----------------------------------------------------------------------
# 9️⃣  Run the test suite (including ps_roi_align test)
# ----------------------------------------------------------------------
echo "🚦 Running test suite ..."
Rscript -e "devtools::test('${PKG_ROOT}')"

echo "🎉 All done – cached torchvision source lives at ${TORCHVISION_CACHE}"

# Show compiler information
if [[ "${RESTORE_MAKEVARS}" == "true" ]]; then
  echo ""
  echo "ℹ️  Note: This build used the system compiler for ABI compatibility with torch"
  echo "   Your original Makevars has been restored for other packages"
  echo "   Backup available at: ${MAKEVARS_BACKUP}"
fi

