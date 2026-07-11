# Build Tools

## setup_build_env.sh

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
