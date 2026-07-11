# Build {torchvisionlib}

## Package folder organization

1. The package’s build system – what the files mean

| Directory / File      | What it does                                                                                                                                                                                                                                                                                                    |
| ------| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `src/Makevars`        | Very small – only sets `PKG_CPPFLAGS` and `PKG_LIBS`. The heavy lifting is not done here.                                                                                                                                                                                                                       |
| `csrc/CMakeLists.txt` | Full CMake project that (a) finds the torch installation, (b) builds the external library `libtorchvision.so` (by cloning pytorch/vision), (c) builds the wrapper library `torchvisionlib` (the one that contains the R‑cpp exported symbols), (d) installs the results into the R package’s `inst/` directory. |
| `R/`                  | Pure‑R code – the `.onLoad()` routine that loads the two shared objects (`libtorchvision.so` and `torchvisionlib.so`).                                                                                                                                                                                          |
| `src/`                | Only contains a few tiny C++ files (`ops.cpp`, `exports.cpp`, …) that are linked into `torchvisionlib.so` by CMake. They are not compiled by the default Makefile.                                                                                                                                              |
| `inst/`               | Destination where CMake copies the compiled libraries. At install time the files end up in the user library, e.g. `~/R/x86_64‑pc‑linux‑gnu‑library/4.5/torchvisionlib/libs/`.                                                                                                                                   |


# daily rebuild all

## How to work on the package 
Action 	Command
Add a new C++ function (e.g. a new ops_… implementation)\ 	
  1) Add the source file to csrc/src/ (or modify an existing one). <br>
  2) Ensure it is **listed in the variable TORCHVISION_SRC** inside csrc/CMakeLists.txt @153.\
  3) Run Rcpp::compileAttributes() (or ./tools/build_and_install.sh which does it automatically).\
Re‑compile after a change\ 	
  ./tools/build_and_install.sh – the script cleans the CMake build directory and rebuilds everything, then reinstalls the R package.\
Run the full test suite\ 	
  devtools::test() or Rscript -e "devtools::test()".\
Debug a missing symbol\ 	
  After reinstall, check the exported symbols: <br> `nm -D $(Rscript -e "cat(file.path(system.file('libs', package='torchvisionlib'), 'torchvisionlib.so'))")\

##  TL;DR – short version
```bash
cd torchvisionlib
# From the root of the package (where DESCRIPTION lives)
# 1) Run the helper script (creates both .so files and installs the package)
./tools/build_and_install.sh

# 2) If you just want to run the single test, start a fresh R session:
R
> library(torchvisionlib)
> # the test you posted now works without error
```

After those two commands the missing symbol error disappears, the nn_ps_roi_align operator is usable, and the unit test you wrote passes.

##  setup_build_env.sh (rebuild torchvisionlib only) (obsolete) 


This script sets up the necessary environment variables for compiling the torchvisionlib R package when using the simplified `src/Makevars`.

### Usage

```bash
# Source the script to set environment variables
source tools/setup_build_env.sh

# Then build and install
R CMD build .
R CMD INSTALL torchvisionlib_*.tar.gz

# Or use devtools
Rscript -e "devtools::install()"
```

### What it does

The script automatically:
- Detects the torch package installation paths
- Sets `PKG_CPPFLAGS` with torch include paths
- Sets `PKG_LIBS` with platform-specific linker flags (macOS/Linux)
- Configures CUDA support if `CUDA_HOME` is set
- Sets C++20 standard

### CUDA Support

To enable CUDA compilation, set `CUDA_HOME` before sourcing the script:

```bash
export CUDA_HOME=/usr/local/cuda
source tools/setup_build_env.sh
```

### Environment Variables Set

- `PKG_CPPFLAGS` - Include paths for torch and CUDA
- `PKG_LIBS` - Library paths and linker flags
- `CXX_STD` - C++ standard (CXX20)
- `NVCC`, `NVCCFLAGS`, `OBJECTS` - CUDA-specific (if CUDA_HOME is set)

Needed at eact new version of libtorch, to compile the /vision C++ part of the lib.


Below is a complete, step‑by‑step guide for producing the missing libtorchvision.so (or libtorchvision.dylib on macOS) that the R package torchvisionlib needs.
The guide is written for Ubuntu 24.04 (Linux) but the same commands, with only a few path tweaks, also work on macOS.

1. What really is libtorchvision.so ?

torchvisionlib is a thin C++/R wrapper around the C++ part of torchvision (the same code that powers the Python torchvision package).
torchvision ships a shared library – libtorchvision.so – that contains the implementations of all the ops (e.g. ms_deform_attn, roi_align, …).

The R package does not build that library itself; it expects you to produce it once (with CMake) and then copy the resulting file into the package’s src/ directory. After that, the R Makevars script only has to patch its r‑path and link against it.

2. Prerequisites (what you need on the system)

Tool / library 	Minimum version 	Install command (Ubuntu)
Git 	any 	sudo apt-get install git
CMake 	≥ 3.18 (≥ 3.22 is safest) 	sudo apt-get install cmake
GCC / G++ 	≥ 9 (C++17 support) 	sudo apt-get install build-essential
CUDA (optional) 	≥ 11.8 (if you want GPU support) 	sudo apt-get install nvidia-cuda-toolkit
Patchelf (Linux r‑path tool) 	any 	sudo apt-get install patchelf
R package torch 	already installed (provides libtorch) 	install.packages("torch")

> Note: The torch R package already downloaded a pre‑built > libtorch binary into your R library directory, e.g.
```
/home/creg/R/x86_64-pc-linux-gnu-library/4.5/torch/
├─ include/
└─ lib/
   ├─ libtorch.so
   ├─ libtorch_cpu.so
   └─ libtorch_cuda.so   (if you installed the CUDA version)
```

We will point CMake to that directory ($TORCH_LIB_PATH and $TORCH_INCLUDE_PATH are 
already computed by the script you sourced).

3. Get the C++ source of torchvision

The part we need lives in the PyTorch/vision repository under the folder torchvision/csrc. 
Clone it once (you can keep it anywhere, e.g. ~/src/torchvision).
```
# Choose a convenient place for the source
mkdir -p ~/src && cd ~/src
git clone https://github.com/pytorch/vision.git
cd vision
# Optional – checkout a tag that matches the libtorch version you have.
# For example, if the torch R package uses libtorch 2.7.1:
<<<<<<< HEAD
git checkout v0.23.0   # (v0.23.0 corresponds to libtorch 2.8.0 matching {torch} 0.18.0)
=======
git checkout v0.22   # (v0.22.x corresponds to libtorch 2.7.1)
>>>>>>> 292243d10cdf752c15a9ea6ddde889d3e04b0726
```
> Why a tag?
> libtorch and torchvision must be binary compatible. The 
> torchvision releases are tied to a particular PyTorch version, 
> see the table in the repo’s README. Pick the tag that matches the 
> version recorded in [torch compatibility matrix](https://torch.mlverse.org/docs/dev/articles/compatibility-matrix).
```

```

Corresponding torchvision tag: v0.18.1.

4. Configure CMake – point it at the libtorch you already have

Create a build directory inside the cloned repo and call cmake with the right options.
```
cd ~/src/vision                # the repository root
mkdir -p build && cd build
```
Now run CMake. The two most important variables are:
Variable 	Meaning
CMAKE_PREFIX_PATH 	Directory that contains both include/torch and lib/libtorch.so. We give it the parent of the lib folder ($TORCH_LIB_PATH/..).
BUILD_SHARED_LIBS 	ON tells CMake to produce a shared object (.so).
TORCHVISION_BUILD_CPP 	ON builds the C++ library without the Python bindings (the only thing we need).
CMAKE_INSTALL_PREFIX 	Where you want the final libtorchvision.so to end up – we will later copy it to the R package src/. For now we can set it to a temporary folder.

``` bash
# Pull the paths that the sourcing script already computed:
TORCH_INCLUDE_PATH=$(Rscript -e "cat(system.file('include/torch/csrc/api/include', package = 'torch'))" | tail -n1)
TORCH_LIB_PATH=$(Rscript -e "cat(system.file('lib', package = 'torch'))" | tail -n1)

# Run CMake
cmake .. \
  -DCMAKE_PREFIX_PATH="${TORCH_LIB_PATH}/.." \
  -DCMAKE_INSTALL_PREFIX="${PWD}/install" \
  -DBUILD_SHARED_LIBS=ON \
  -DTORCHVISION_BUILD_CPP=ON \
  -DCMAKE_BUILD_TYPE=Release

```
Explanation of the key lines

    -DCMAKE_PREFIX_PATH="${TORCH_LIB_PATH}/.."
    CMAKE_PREFIX_PATH must point to the root that contains both the include/torch and the lib directory.
    Example:

```
~/R/x86_64-pc-linux-gnu-library/4.5/torch/
  ├─ include/
  │   └─ torch/…
  └─ lib/
      └─ libtorch.so
```


The parent of lib (…/torch) satisfies this requirement.

    -DTORCHVISION_BUILD_CPP=ON
    Disables the Python bindings (torchvision PyPI package) and only builds the pure C++ part.

    -DBUILD_SHARED_LIBS=ON
    Produces libtorchvision.so. If you set this to OFF you would get a static archive (.a), which the R package cannot link to directly.

5. Build the library

# Use all available cores – on Ubuntu 24.04 you have at least 4.
```
make -j$(nproc)
```

When make finishes you will see the shared object in the build tree, e.g.

```
build/lib/libtorchvision.so
```

You can verify it with file:
```
file lib/libtorchvision.so
```
# → libtorchvision.so: ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), …

6. Install / copy the result into the R package
6.1. Quick copy (manual)

The torchvisionlib R package expects the library to live in its src/ folder. From the build directory:
```
# Destination inside the R package (adjust the path if you are in a different location)
cp lib/libtorchvision.so /home/creg/R/_packages/torchvisionlib/src/
```

6.2. (Optional) make install into a temporary location

If you used -DCMAKE_INSTALL_PREFIX=…/install you can also run
```bash
make install
# This puts libtorchvision.so into …/install/lib/

# and then copy:

cp install/lib/libtorchvision.so /home/creg/R/_packages/torchvisionlib/src/

# Both approaches give the same file.
# 7. Verify that the file is now where the script expects it
ls -l /home/creg/R/_packages/torchvisionlib/src/libtorchvision.so
# should display the file with size ~ a few MB
```
Now re‑run the setup script you sourced earlier:

```source /home/creg/R/_packages/torchvisionlib/tools/setup_build_env.sh```

You should see no error about a missing external library. The script will patch the r‑path (with patchelf) and copy the library to ../inst/lib/.
8. Build the R package


``` bash
# From the package root (where the DESCRIPTION file lives)
R CMD INSTALL .
# or, with devtools:
Rscript -e "devtools::install()"
```
If everything went fine you will see the compilation of the C++ sources (ms_deform_attn.cpp, etc.) and a final linking line that refers to -ltorchvision – the library we just built.
9. Full reproducible script (optional)

If you want to automate the whole process – from cloning the repo to copying the library – 
you can add the following to a new file tools/build_libtorchvision.sh and run it once before the first package build.

```bash 
#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------
# 1. Get torch locations (identical to the R setup script)
# ------------------------------------------------------------------
TORCH_INCLUDE_PATH=$(Rscript -e "cat(system.file('include/torch/csrc/api/include', package = 'torch'))" | tail -n1)
TORCH_LIB_PATH=$(Rscript -e "cat(system.file('lib', package = 'torch'))" | tail -n1)

# ------------------------------------------------------------------
# 2. Determine matching torchvision tag
# ------------------------------------------------------------------
TORCH_VER=$(Rscript -e "cat(torch:::torch_version)")
# Mapping table (add entries if new versions appear)
declare -A TAGMAP=(
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
SRC_ROOT="${HOME}/src/vision"
if [[ -d "$SRC_ROOT/.git" ]]; then
  echo "Updating existing clone ..."
  git -C "$SRC_ROOT" fetch --tags
else
  echo "Cloning torchvision ..."
  git clone https://github.com/pytorch/vision.git "$SRC_ROOT"
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
DEST_SRC="${PKG_ROOT}/src"
mkdir -p "$DEST_SRC"
cp lib/libtorchvision.so "$DEST_SRC/"

echo "libtorchvision.so successfully copied to $DEST_SRC"
echo "Now run:"
echo "    source ${PKG_ROOT}/tools/setup_build_env.sh"
echo "    R CMD INSTALL ${PKG_ROOT}"
```

Make it executable (chmod +x tools/build_libtorchvision.sh) and run:

```bash
cd /home/creg/R/_packages/torchvisionlib
./tools/build_libtorchvision.sh
```
After it finishes, follow the two last lines it prints: source the environment script and install the package.
10. TL;DR checklist
Step 	Command (run from a terminal)
(a) Get torch paths         – already done by your script. 	
(b) Clone torchvision 	    git clone https://github.com/pytorch/vision.git ~/src/vision
(c) Checkout matching tag 	cd ~/src/vision && git checkout v0.18.1
(d) Configure CMake 	      <pre>cd ~/src/vision && mkdir -p build && cd build<br>cmake .. -DCMAKE_PREFIX_PATH="${TORCH_LIB_PATH}/.." -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DTORCHVISION_BUILD_CPP=ON</pre>
(e) Build 	                make -j$(nproc)
(f) Copy the result 	      cp build/lib/libtorchvision.so /home/creg/R/_packages/torchvisionlib/src/
(g) Source env script again 	source /home/creg/R/_packages/torchvisionlib/tools/setup_build_env.sh
(h) Install the R package 	R CMD build . && R CMD INSTALL .(or devtools::install())
(i) Check 2 expected `.so` files are installed and patched
```bash
INST_LIB=$(Rscript -e "cat(file.path(system.file('libs', package='torchvisionlib')))")
ls -l "$INST_LIB""

#> -rwxrwxr-x 1 creg creg 1581112 févr. 21 15:56 libtorchvision.so
#> -rwxrwxr-x 1 creg creg 2016248 févr. 21 15:56 torchvisionlib.so
readelf -d "$INST_LIB/libtorchvision.so" | grep RUNPATH
#>  0x000000000000001d (RUNPATH)            Bibliothèque runpath :[~/R/x86_64-pc-linux-gnu-library/4.5/torch/lib]
```
Once you have performed (a)–(f) once, you can rebuild the R package any number of times simply by re‑sourcing the script and calling R CMD INSTALL. No further CMake step is required unless you upgrade torch or want a different torchvision version.

