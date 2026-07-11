#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------
# 1. Get torch locations (shall exist in env after a source/setup_build_env.sh)
# ------------------------------------------------------------------
TORCH_INCLUDE_PATH=$(Rscript -e "cat(system.file('include/torch/csrc/api/include', package = 'torch'))" | tail -n1)
TORCH_LIB_PATH=$(Rscript -e "cat(system.file('lib', package = 'torch'))" | tail -n1)

# ------------------------------------------------------------------
# 2. Determine matching torchvision tag (or do it manually)
# ------------------------------------------------------------------
# TORCH_VER=$(Rscript -e "cat(torch:::torch_version)") # fails
TORCH_VER="2.8.0" # {torch} 0.17.0
# Mapping table (add entries if new versions appear)
declare -A TAGMAP=(
  ["2.13.0"]="v0.28.0"
  ["2.12.0"]="v0.27.0"
  ["2.11.0"]="v0.26.0"
  ["2.10.0"]="v0.25.0"
  ["2.9.0"]="v0.24.1"
  ["2.8.0"]="v0.23.0"
  ["2.7.1"]="v0.22.1"
  ["2.5.1"]="v0.20.1"
  ["2.0.1"]="v0.15.2"
)
VISION_TAG=${TAGMAP[$TORCH_VER]:-}
if [[ -z "$VISION_TAG" ]]; then
  echo "ERROR: No torchvision tag known for torch version $TORCH_VER"
  exit 1
fi
echo "Using torchvision tag $VISION_TAG for torch $TORCH_VER"

# ------------------------------------------------------------------
# 3. Clone (or update) the source
# ------------------------------------------------------------------
SRC_ROOT="${HOME}/python/src/vision"
if [[ -d "$SRC_ROOT/.git" ]]; then
  echo "Updating existing clone ..."
  git -C "$SRC_ROOT" fetch --tags
else
  echo "Cloning torchvision branch tag $VISION_TAG ..."
  git clone -C "$SRC_ROOT" https://github.com/pytorch/vision.git "$SRC_ROOT"
fi
git -C "$SRC_ROOT" checkout "$VISION_TAG"

# ------------------------------------------------------------------
# 4. Build
# ------------------------------------------------------------------
cd "$SRC_ROOT"
mkdir -p build && cd build
cmake .. \
  -DCMAKE_PREFIX_PATH="${TORCH_LIB_PATH}/.." \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON \
  -DTORCHVISION_BUILD_CPP=ON
make -j$(nproc)


# ------------------------------------------------------------------
# 5. Install to the R package
# ------------------------------------------------------------------
PKG_ROOT="${HOME}/R/_packages/torchvisionlib"   # <-- adjust if you installed elsewhere
DEST_SRC="${PKG_ROOT}/inst/libs"
mkdir -p "$DEST_SRC"
cp libtorchvision.so "$DEST_SRC/"

echo "libtorchvision.so successfully copied to $DEST_SRC"
echo "Now run:"
echo "    source ${PKG_ROOT}/tools/setup_build_env.sh"
echo "    R CMD INSTALL ${PKG_ROOT}"


