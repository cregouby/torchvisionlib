#!/usr/bin/env bash
# ----------------------------------------------------------------------
# script follow tools/build_and_install.sh
#
# Complete build script for torchvisionlib R package by running tests.
# ----------------------------------------------------------------------
set -euo pipefail

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
