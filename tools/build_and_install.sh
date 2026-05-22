#!/usr/bin/env bash
# ----------------------------------------------------------------------
# tools/build_and_install.sh
#
# Complete build script for torchvisionlib R package.
# ----------------------------------------------------------------------
set -euo pipefail

# ======================================================================
# 0. Configuration
# ======================================================================
PKG_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
C_SRC="${PKG_ROOT}/csrc"
BUILD_DIR="${C_SRC}/build"
INST_DIR="${PKG_ROOT}/inst"
INST_LIBS="${INST_DIR}/libs"
SRC_DIR="${PKG_ROOT}/src"
TORCHVISION_CACHE="${HOME}/.cache/torchvision"
TORCHVISION_TAG="v0.22.1"

mkdir -p "${INST_LIBS}"

echo "=============================================="
echo "  torchvisionlib Build Script"
echo "=============================================="
echo "Package root: ${PKG_ROOT}"
echo "=============================================="

# ======================================================================
# 1. Prepare torchvision Source
# ======================================================================
echo ""
echo ">>> Step 1: Preparing torchvision source..."

mkdir -p "${TORCHVISION_CACHE}"

if [[ -d "${TORCHVISION_CACHE}/.git" ]]; then
    echo "    Using cached torchvision at ${TORCHVISION_CACHE}"
    git -C "${TORCHVISION_CACHE}" fetch --tags --quiet 2>/dev/null || true
    git -C "${TORCHVISION_CACHE}" checkout "${TORCHVISION_TAG}" --quiet 2>/dev/null || true
    git -C "${TORCHVISION_CACHE}" pull --ff-only origin "${TORCHVISION_TAG}" --quiet 2>/dev/null || true
else
    echo "    Cloning torchvision (${TORCHVISION_TAG})..."
    git clone --depth 1 --branch "${TORCHVISION_TAG}" \
        https://github.com/pytorch/vision "${TORCHVISION_CACHE}"
fi
echo "    ✓ Torchvision source ready"

# ======================================================================
# 2. Locate Torch Installation
# ======================================================================
echo ""
echo ">>> Step 2: Locating torch installation..."

TORCH_PATH=$(Rscript --vanilla -e "cat(torch::torch_install_path())" 2>/dev/null || echo "")

if [[ -z "${TORCH_PATH}" ]] || [[ ! -d "${TORCH_PATH}" ]]; then
    echo "    ✗ ERROR: torch package not found"
    exit 1
fi

TORCH_LIB_PATH=$(Rscript --vanilla -e "cat(system.file('lib', package = 'torch'))" 2>/dev/null || echo "")

if [[ -z "${TORCH_LIB_PATH}" ]]; then
    echo "    ✗ ERROR: Could not find torch library directory"
    exit 1
fi

TORCH_INC_PATH=$(Rscript --vanilla -e "cat(system.file('include', package = 'torch'))" 2>/dev/null || echo "")

echo "    ✓ Torch home:  ${TORCH_PATH}"
echo "    ✓ Torch libs:  ${TORCH_LIB_PATH}"
echo "    ✓ Torch inc:   ${TORCH_INC_PATH}"

# ======================================================================
# 3. Build Native Libraries with CMake
# ======================================================================
echo ""
echo ">>> Step 3: Building native libraries with CMake..."

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

cmake .. \
    -DCMAKE_INSTALL_PREFIX="${INST_DIR}" \
    -DTORCH_HOME="${TORCH_PATH}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_LOCAL_TORCHVISION=ON \
    -DTORCHVISION_SOURCE_DIR="${TORCHVISION_CACHE}"

NCORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
cmake --build . --target install -- -j"${NCORES}"

echo "    ✓ CMake build complete"

# ======================================================================
# 4. Verify Libraries
# ======================================================================
echo ""
echo ">>> Step 4: Verifying libraries..."

if [[ "$(uname)" == "Darwin" ]]; then
    LIB_EXT="dylib"
else
    LIB_EXT="so"
fi

TORCHVISION_LIB="${INST_LIBS}/libtorchvision.${LIB_EXT}"
TORCHVISIONLIB_LIB="${INST_LIBS}/libtorchvisionlib.${LIB_EXT}"

if [[ ! -f "${TORCHVISION_LIB}" ]]; then
    echo "    ✗ ERROR: libtorchvision.${LIB_EXT} not found"
    exit 1
fi
echo "    ✓ libtorchvision.${LIB_EXT}"

if [[ ! -f "${TORCHVISIONLIB_LIB}" ]]; then
    for search_dir in "${BUILD_DIR}" "${BUILD_DIR}/lib"; do
        if [[ -f "${search_dir}/libtorchvisionlib.${LIB_EXT}" ]]; then
            cp "${search_dir}/libtorchvisionlib.${LIB_EXT}" "${INST_LIBS}/"
            TORCHVISIONLIB_LIB="${INST_LIBS}/libtorchvisionlib.${LIB_EXT}"
            break
        fi
    done
fi

if [[ ! -f "${TORCHVISIONLIB_LIB}" ]]; then
    echo "    ✗ ERROR: libtorchvisionlib.${LIB_EXT} not found"
    exit 1
fi
echo "    ✓ libtorchvisionlib.${LIB_EXT}"

chmod +x "${TORCHVISION_LIB}" "${TORCHVISIONLIB_LIB}"

echo ""
echo "    Libraries in inst/libs/:"
ls -la "${INST_LIBS}/"*.${LIB_EXT} 2>/dev/null || true

# ======================================================================
# 5. Patch RPATH
# ======================================================================
echo ""
echo ">>> Step 5: Patching RPATH..."

if [[ "$(uname)" == "Linux" ]]; then
    if command -v patchelf >/dev/null 2>&1; then
        patchelf --set-rpath "\$ORIGIN:${TORCH_LIB_PATH}" "${TORCHVISIONLIB_LIB}" 2>/dev/null || true
        patchelf --set-rpath "${TORCH_LIB_PATH}" "${TORCHVISION_LIB}" 2>/dev/null || true
        echo "    ✓ RPATH patched"
    fi
elif [[ "$(uname)" == "Darwin" ]]; then
    install_name_tool -add_rpath "@loader_path" "${TORCHVISIONLIB_LIB}" 2>/dev/null || true
    install_name_tool -add-rpath "${TORCH_LIB_PATH}" "${TORCHVISIONLIB_LIB}" 2>/dev/null || true
    install_name_tool -add_rpath "${TORCH_LIB_PATH}" "${TORCHVISION_LIB}" 2>/dev/null || true
    echo "    ✓ RPATH patched"
fi

# ======================================================================
# 6. Generate R Documentation
# ======================================================================
echo ""
echo ">>> Step 6: Generating R documentation..."

cd "${PKG_ROOT}"
export _R_ROXYGEN2_LOAD_=false

Rscript --vanilla -e "Rcpp::compileAttributes('${PKG_ROOT}', verbose = FALSE)" 2>&1 | head -5 || true
Rscript --vanilla -e "torchexport::export('${PKG_ROOT}')" 2>&1 | head -5 || true
Rscript --vanilla -e "options(roxygen2.load = FALSE); roxygen2::roxygenize('${PKG_ROOT}')" 2>&1 | head -10 || true

echo "    ✓ Documentation generated"

# ======================================================================
# 6b. Fix NAMESPACE
# ======================================================================
echo ""
echo ">>> Step 6b: Fixing NAMESPACE..."

sed -i 's/sourceRcpp/sourceCpp/g' "${PKG_ROOT}/NAMESPACE" 2>/dev/null || true
sed -i 's/sourceRcpp/sourceCpp/g' "${PKG_ROOT}/R/RcppExports.R" 2>/dev/null || true
echo "    ✓ NAMESPACE fixed"

# ======================================================================
# 7. Create configure script
# ======================================================================
echo ""
echo ">>> Step 7: Creating configure script..."

cat > "${PKG_ROOT}/configure" << 'CONFIGURE_EOF'
#!/bin/bash
set -e
echo "Configuring torchvisionlib..."

TORCH_LIB=$(Rscript --vanilla -e "cat(system.file('lib', package = 'torch'))" 2>/dev/null || echo "")
if [ -z "$TORCH_LIB" ] || [ ! -d "$TORCH_LIB" ]; then
    echo "ERROR: torch package not found"
    exit 1
fi

TORCH_INC=$(Rscript --vanilla -e "cat(system.file('include', package = 'torch'))" 2>/dev/null || echo "")
[ -z "$TORCH_INC" ] && TORCH_INC="${TORCH_LIB}/../include"

INST_LIBS="$(pwd)/inst/libs"

echo "  Found torch libs: $TORCH_LIB"
echo "  INST_LIBS: $INST_LIBS"

cat > src/Makevars << MAKEVARS_EOF
# Auto-generated by configure
CXX_STD = CXX17
PKG_CPPFLAGS = -I../inst/include -I${TORCH_INC}
PKG_LIBS = -L${INST_LIBS} -L${TORCH_LIB} -ltorchvisionlib -ltorch -lc10 -Wl,-rpath,${INST_LIBS} -Wl,-rpath,${TORCH_LIB}
MAKEVARS_EOF

echo "Configuration complete."
CONFIGURE_EOF

chmod +x "${PKG_ROOT}/configure"
echo "    ✓ configure script created"

# ======================================================================
# 8. Install R Package
# ======================================================================
echo ""
echo ">>> Step 8: Installing R package..."

cd "${PKG_ROOT}"

# Export LD_LIBRARY_PATH for all child processes
export LD_LIBRARY_PATH="${INST_LIBS}:${TORCH_LIB_PATH}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

echo "    LD_LIBRARY_PATH = ${LD_LIBRARY_PATH}"

if [[ "$(uname)" == "Darwin" ]]; then
    export DYLD_FALLBACK_LIBRARY_PATH="${INST_LIBS}:${TORCH_LIB_PATH}${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
fi

# Install with --install-tests so test_package() works
R CMD INSTALL --install-tests --no-multiarch --with-keep.source "${PKG_ROOT}" 2>&1 | \
    tee /tmp/torchvisionlib_install.log

if tail -5 /tmp/torchvisionlib_install.log | grep -q "ERROR"; then
    echo ""
    echo "    ✗ Installation failed!"
    cat /tmp/torchvisionlib_install.log
    exit 1
fi

echo "    ✓ Package installed"

# ======================================================================
# 9. Verify Installation
# ======================================================================
echo ""
echo ">>> Step 9: Verifying installation..."

Rscript --vanilla -e "library(torchvisionlib); cat('✓ Package loads successfully\n')" 2>&1

# ======================================================================
# 10. Run Tests on INSTALLED package
# ======================================================================
echo ""
echo ">>> Step 10: Running tests..."
echo "    Testing installed package (not source)"
echo ""

# Test the INSTALLED package, not source
# This ensures the .so file from the installation is used
Rscript --vanilla -e "
# Verify we're testing the installed package
cat('Package location:', system.file('', package = 'torchvisionlib'), '\n')
cat('Library .so files:\n')
print(list.files(file.path(system.file('', package = 'torchvisionlib'), 'libs'), pattern = '\\\\.so$'))

# Run tests on the installed package
testthat::test_package('torchvisionlib', reporter = 'summary')
" 2>&1 | tail -60

echo ""
echo "=============================================="
echo "  ✓ Build Complete!"
echo "=============================================="
echo ""
echo "  Libraries: ${INST_LIBS}"
ls -la "${INST_LIBS}/"*.${LIB_EXT} 2>/dev/null | awk '{print "    " $NF}'
echo ""
echo "  To use: library(torchvisionlib)"
echo ""
echo "  To run tests manually:"
echo "    Rscript -e \"testthat::test_package('torchvisionlib')\""
echo "=============================================="

