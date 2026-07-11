#' Situational report for torchvisionlib installation
#'
#' Provides diagnostic information about the torchvisionlib installation,
#' including torch availability, binary installation status, CUDA support,
#' library paths, and system information. Useful for troubleshooting
#' installation and build issues.
#'
#' @return Invisibly returns a list with diagnostic information. The function
#'   is primarily called for its side effect of printing a formatted report.
#'
#' @examples
#' \dontrun{
#' torchvisionlib_sitrep()
#' }
#'
#' @export
torchvisionlib_sitrep <- function() {
  report <- list()

  cli::cli_h1("torchvisionlib Situational Report")

  # Package information
  cli::cli_h2("Package Information")
  pkg_version <- packageDescription("torchvisionlib")$Version
  cli::cli_alert_info("torchvisionlib version: {pkg_version}")
  report$package_version <- pkg_version

  inst_dir <- inst_path()
  cli::cli_alert_info("Installation directory: {inst_dir}")
  report$inst_path <- inst_dir

  # Check if running from development source
  is_dev <- file.exists(file.path(inst_dir, "csrc"))
  if (is_dev) {
    cli::cli_alert_info("Running from development source")
    report$is_dev <- TRUE
  } else {
    report$is_dev <- FALSE
  }

  # System information
  cli::cli_h2("System Information")
  os_type <- get_cmake_style_os()
  cli::cli_alert_info("OS: {os_type} ({R.version$os})")
  cli::cli_alert_info("Architecture: {R.version$arch}")
  report$os <- os_type
  report$arch <- R.version$arch

  # Torch installation
  cli::cli_h2("Torch Installation")
  torch_installed <- requireNamespace("torch", quietly = TRUE)

  if (torch_installed) {
    cli::cli_alert_success("torch package is installed")
    report$torch_installed <- TRUE

    if (torch::torch_is_installed()) {
      cli::cli_alert_success("LibTorch binaries are installed")
      report$libtorch_installed <- TRUE

      torch_version <- torch:::torch_version
      cli::cli_alert_info("torch version: {torch_version}")
      report$torch_version <- torch_version

      # CUDA information
      cuda_available <- torch::cuda_is_available()
      if (cuda_available) {
        cli::cli_alert_success("CUDA is available")
        report$cuda_available <- TRUE

        cuda_version <- torch::cuda_runtime_version()
        cuda_ver_str <- paste0(cuda_version[1,1], ".", cuda_version[1,2])
        cli::cli_alert_info("CUDA version: {cuda_ver_str}")
        report$cuda_version <- cuda_ver_str
      } else {
        cli::cli_alert_info("CUDA is not available (CPU-only)")
        report$cuda_available <- FALSE
      }
    } else {
      cli::cli_alert_danger("LibTorch binaries are NOT installed")
      cli::cli_alert_info("Run: torch::install_torch()")
      report$libtorch_installed <- FALSE
    }
  } else {
    cli::cli_alert_danger("torch package is NOT installed")
    cli::cli_alert_info("Install torch first: install.packages('torch')")
    report$torch_installed <- FALSE
  }

  # Torchvisionlib binary installation
  cli::cli_h2("Torchvisionlib Binaries")
  tvl_installed <- torchvisionlib_is_installed()

  if (tvl_installed) {
    cli::cli_alert_success("torchvisionlib binaries are installed")
    report$binaries_installed <- TRUE

    # Show library paths
    tvl_lib <- lib_path("torchvisionlib")
    tv_lib <- lib_path("torchvision")

    cli::cli_alert_info("torchvisionlib: {tvl_lib}")
    cli::cli_alert_info("  Exists: {file.exists(tvl_lib)}")
    cli::cli_alert_info("  Size: {format_file_size(tvl_lib)}")

    if (.Platform$OS.type == "unix" && !grepl("mingw", R.version[["os"]])) {
      cli::cli_alert_info("torchvision: {tv_lib}")
      cli::cli_alert_info("  Exists: {file.exists(tv_lib)}")
      cli::cli_alert_info("  Size: {format_file_size(tv_lib)}")
    }

    report$lib_paths <- list(
      torchvisionlib = tvl_lib,
      torchvision = if (.Platform$OS.type == "unix" && !grepl("mingw", R.version[["os"]])) tv_lib else NULL
    )
  } else {
    cli::cli_alert_danger("torchvisionlib binaries are NOT installed")
    report$binaries_installed <- FALSE

    # Show where binaries would be installed
    expected_path <- lib_path("torchvisionlib")
    cli::cli_alert_info("Expected location: {expected_path}")
    report$expected_lib_path <- expected_path

    # Show download URL
    if (torch_installed && torch::torch_is_installed()) {
      dev <- if (torch::cuda_is_available()) "cu" else "cpu"

      if (grepl("darwin", R.version$os)) {
        if (grepl("aarch64", R.version$arch)) {
          dev <- paste0(dev, "+arm64")
        } else {
          dev <- paste0(dev, "+x86_64")
        }
      }

      if (dev == "cu") {
        runtime_version <- torch::cuda_runtime_version()
        dev <- paste0(dev, runtime_version[1,1], runtime_version[1,2])
      }

      expected_url <- sprintf(
        "https://github.com/mlverse/torchvisionlib/releases/download/v%s/torchvisionlib-%s+%s-%s.zip",
        pkg_version, pkg_version, dev, os_type
      )

      cli::cli_alert_info("Expected binary URL:")
      cli::cli_alert_info("  {expected_url}")
      report$expected_url <- expected_url
    }

    cli::cli_alert_info("Run: torchvisionlib::install_torchvisionlib()")
  }

  # Environment variables
  cli::cli_h2("Environment Variables")

  env_vars <- c("TORCHVISIONLIB_HOME", "TORCHVISIONLIB_URL", "TORCH_INSTALL",
                "CUDA_HOME", "USE_LOCAL_TORCHVISION", "TORCHVISION_SOURCE_DIR")

  any_set <- FALSE
  for (var in env_vars) {
    val <- Sys.getenv(var, unset = "")
    if (nzchar(val)) {
      cli::cli_alert_info("{var}: {val}")
      any_set <- TRUE
      report$env_vars[[var]] <- val
    }
  }

  if (!any_set) {
    cli::cli_alert_info("No relevant environment variables set")
  }

  # Build tools and configuration
  cli::cli_h2("Build Tools & Configuration")

  # Check for cmake
  cmake_available <- nzchar(Sys.which("cmake"))
  if (cmake_available) {
    cmake_version <- tryCatch({
      system("cmake --version", intern = TRUE)[1]
    }, error = function(e) "unknown")
    cli::cli_alert_success("cmake: {cmake_version}")
    report$cmake <- cmake_version
  } else {
    cli::cli_alert_warning("cmake not found in PATH")
    report$cmake <- FALSE
  }

  # Check torch's C++ ABI and library versions (macOS specific)
  if (torch_installed && torch::torch_is_installed() && grepl("darwin", R.version$os)) {
    torch_lib <- file.path(system.file("lib", package = "torch"), "libtorch_cpu.dylib")

    if (file.exists(torch_lib)) {
      # Check torch's libc++ version
      torch_deps <- tryCatch({
        system2("otool", c("-L", torch_lib), stdout = TRUE, stderr = FALSE)
      }, error = function(e) NULL)

      if (!is.null(torch_deps)) {
        libc_line <- grep("libc\\+\\+", torch_deps, value = TRUE)
        if (length(libc_line) > 0) {
          cli::cli_alert_info("torch libc++ dependency:")
          cli::cli_alert_info("  {trimws(libc_line)}")

          # Extract version number (e.g., 1700.255.5)
          version_match <- regmatches(libc_line, regexpr("\\d+\\.\\d+\\.\\d+", libc_line))
          if (length(version_match) > 0) {
            report$torch_libcxx_version <- version_match[1]
          }
        }
      }
    }

    # Check current SDK
    current_sdk <- Sys.getenv("SDKROOT", unset = "")
    if (nzchar(current_sdk)) {
      cli::cli_alert_info("Current SDKROOT: {current_sdk}")
      report$current_sdk <- current_sdk
    } else {
      # Try to detect default SDK
      xcrun_sdk <- tryCatch({
        system2("xcrun", c("--show-sdk-path"), stdout = TRUE, stderr = FALSE)
      }, error = function(e) NULL)

      if (!is.null(xcrun_sdk) && length(xcrun_sdk) > 0) {
        cli::cli_alert_info("Default SDK: {xcrun_sdk}")
        report$current_sdk <- xcrun_sdk
      }
    }
  }

  # Check for C++ compiler
  if (.Platform$OS.type == "unix") {
    # Check Makevars
    makevars_path <- if (grepl("darwin", R.version$os)) {
      "~/.R/Makevars"
    } else {
      "~/.R/Makevars"
    }
    makevars_path <- path.expand(makevars_path)

    if (file.exists(makevars_path)) {
      cli::cli_alert_info("Makevars found: {makevars_path}")
      report$makevars_path <- makevars_path

      # Read and check for compiler settings
      makevars <- readLines(makevars_path, warn = FALSE)
      cxx_lines <- grep("^CXX|^CC", makevars, value = TRUE)

      if (length(cxx_lines) > 0) {
        cli::cli_alert_info("Compiler settings in Makevars:")
        for (line in cxx_lines) {
          cli::cli_alert_info("  {line}")
        }

        # Check if specified compilers exist
        for (line in cxx_lines) {
          if (grepl("=", line)) {
            parts <- strsplit(line, "=")[[1]]
            if (length(parts) >= 2) {
              compiler_spec <- trimws(parts[2])
              # Extract just the compiler path (first token)
              compiler_path <- strsplit(compiler_spec, " ")[[1]][1]

              if (grepl("^/", compiler_path)) {
                # Absolute path - check if it exists
                if (!file.exists(compiler_path)) {
                  cli::cli_alert_danger("Compiler not found: {compiler_path}")
                  report$compiler_issues <- c(report$compiler_issues, compiler_path)
                } else {
                  cli::cli_alert_success("Compiler exists: {compiler_path}")
                }
              }
            }
          }
        }
      }
      report$makevars_content <- cxx_lines
    } else {
      cli::cli_alert_info("No custom Makevars file (using R defaults)")
      report$makevars_path <- NULL
    }

    # Check for common compilers
    compilers <- c("g++", "clang++", "c++")
    found_compilers <- character()
    for (comp in compilers) {
      comp_path <- Sys.which(comp)
      if (nzchar(comp_path)) {
        found_compilers <- c(found_compilers, paste0(comp, ": ", comp_path))
      }
    }

    if (length(found_compilers) > 0) {
      cli::cli_alert_info("Available compilers:")
      for (comp in found_compilers) {
        cli::cli_alert_info("  {comp}")
      }
      report$available_compilers <- found_compilers
    } else {
      cli::cli_alert_warning("No C++ compilers found in PATH")
      report$available_compilers <- character(0)
    }
  }

  # Development build information (if applicable)
  if (is_dev) {
    cli::cli_h2("Development Build Information")

    # Check for build artifacts
    build_dir <- file.path(inst_dir, "csrc", "build")
    if (file.exists(build_dir)) {
      cli::cli_alert_success("Build directory exists: {build_dir}")
      report$build_dir <- build_dir

      # Check for CMakeCache
      cmake_cache <- file.path(build_dir, "CMakeCache.txt")
      if (file.exists(cmake_cache)) {
        cli::cli_alert_info("CMakeCache.txt found")
        # Extract key information
        cache_lines <- readLines(cmake_cache, warn = FALSE)
        cxx_compiler <- grep("^CMAKE_CXX_COMPILER:FILEPATH=", cache_lines, value = TRUE)
        if (length(cxx_compiler) > 0) {
          compiler <- sub("^CMAKE_CXX_COMPILER:FILEPATH=", "", cxx_compiler[1])
          cli::cli_alert_info("CMake C++ compiler: {compiler}")
          if (!file.exists(compiler)) {
            cli::cli_alert_danger("CMake's configured compiler no longer exists!")
            cli::cli_alert_info("Consider running: rm -rf csrc/build && mkdir csrc/build")
          }
        }
      }
    } else {
      cli::cli_alert_info("No build directory found (binaries may be pre-built)")
    }

    # Check for compiled libraries in inst/libs
    inst_libs <- file.path(inst_dir, "libs")
    if (file.exists(inst_libs)) {
      libs <- list.files(inst_libs, recursive = TRUE, full.names = TRUE)
      if (length(libs) > 0) {
        cli::cli_alert_info("Found {length(libs)} file(s) in inst/libs/")
        for (lib in libs) {
          cli::cli_alert_info("  {basename(lib)} ({format_file_size(lib)})")
        }
        report$inst_libs <- libs
      }
    }

    # Check for proper library linking (on macOS)
    if (grepl("darwin", R.version$os) && file.exists(inst_libs)) {
      tvl_lib <- lib_path("torchvisionlib")
      if (file.exists(tvl_lib)) {
        cli::cli_alert_info("Checking library dependencies (otool -L):")
        deps <- tryCatch({
          system2("otool", c("-L", tvl_lib), stdout = TRUE, stderr = TRUE)
        }, error = function(e) NULL)

        if (!is.null(deps) && length(deps) > 1) {
          # Skip first line (the library itself)
          for (dep in deps[-1]) {
            cli::cli_alert_info("  {trimws(dep)}")
          }
          report$library_deps <- deps
        }
      }
    }
  }

  # Diagnostics and recommendations
  cli::cli_h2("Diagnostics & Recommendations")

  issues_found <- FALSE
  warnings_found <- FALSE

  # Check for compiler issues
  if (!is.null(report$compiler_issues) && length(report$compiler_issues) > 0) {
    issues_found <- TRUE
    cli::cli_alert_danger("Found non-existent compiler paths in Makevars:")
    for (path in report$compiler_issues) {
      cli::cli_alert_info("  {path}")
    }
    cli::cli_alert_info("Fix: Update or remove {makevars_path}")
    cli::cli_alert_info("To use R's default compiler, you can rename/backup your Makevars:")
    cli::cli_alert_info("  mv {makevars_path} {makevars_path}.bak")
  }

  # Check for compiler mismatch (ABI incompatibility risk)
  if (is_dev && !is.null(report$build_dir) && !is.null(report$makevars_content)) {
    cmake_cache <- file.path(report$build_dir, "CMakeCache.txt")
    if (file.exists(cmake_cache)) {
      cache_lines <- readLines(cmake_cache, warn = FALSE)
      cxx_compiler_line <- grep("^CMAKE_CXX_COMPILER:FILEPATH=", cache_lines, value = TRUE)

      if (length(cxx_compiler_line) > 0) {
        cmake_compiler <- sub("^CMAKE_CXX_COMPILER:FILEPATH=", "", cxx_compiler_line[1])

        # Check if compiler still exists
        if (!file.exists(cmake_compiler)) {
          issues_found <- TRUE
          cli::cli_alert_danger("Stale CMake cache with non-existent compiler: {cmake_compiler}")
          cli::cli_alert_info("Fix: Remove and recreate build directory:")
          cli::cli_alert_info("  rm -rf {report$build_dir}")
        }

        # Check for compiler mismatch between CMake and R
        makevars_cxx <- grep("^CXX", report$makevars_content, value = TRUE)
        if (length(makevars_cxx) > 0) {
          # Extract compiler path from Makevars
          for (line in makevars_cxx) {
            if (grepl("^CXX[^F]*=", line)) {  # CXX= but not CXXFLAGS=
              parts <- strsplit(line, "=")[[1]]
              if (length(parts) >= 2) {
                makevars_compiler <- trimws(strsplit(trimws(parts[2]), " ")[[1]][1])

                # Compare compilers
                if (grepl("^/", makevars_compiler) &&
                    !identical(normalizePath(cmake_compiler, mustWork = FALSE),
                              normalizePath(makevars_compiler, mustWork = FALSE))) {
                  issues_found <- TRUE
                  cli::cli_alert_warning("Compiler mismatch detected (ABI incompatibility risk!):")
                  cli::cli_alert_info("  CMake used: {cmake_compiler}")
                  cli::cli_alert_info("  R Makevars: {makevars_compiler}")
                  cli::cli_alert_info("This can cause runtime crashes (bus errors, segfaults)")
                  cli::cli_alert_info("Fix: Ensure both use the same compiler:")
                  cli::cli_alert_info("  1. Clean build: rm -rf {report$build_dir}")
                  cli::cli_alert_info("  2. Update Makevars to match, or remove custom compiler settings")
                }
              }
            }
          }
        }
      }
    }
  }

  # Check for stale CMake cache (separate check)
  if (is_dev && !is.null(report$build_dir)) {
    cmake_cache <- file.path(report$build_dir, "CMakeCache.txt")
    if (file.exists(cmake_cache)) {
      cache_lines <- readLines(cmake_cache, warn = FALSE)
      cxx_compiler <- grep("^CMAKE_CXX_COMPILER:FILEPATH=", cache_lines, value = TRUE)
      if (length(cxx_compiler) > 0) {
        compiler <- sub("^CMAKE_CXX_COMPILER:FILEPATH=", "", cxx_compiler[1])
        if (!file.exists(compiler)) {
          issues_found <- TRUE
          cli::cli_alert_danger("Stale CMake cache with non-existent compiler")
          cli::cli_alert_info("Fix: Remove and recreate build directory:")
          cli::cli_alert_info("  rm -rf {report$build_dir}")
          cli::cli_alert_info("  mkdir {report$build_dir}")
        }
      }
    }
  }

  # Check for missing build tools
  if (.Platform$OS.type == "unix" && !cmake_available) {
    issues_found <- TRUE
    cli::cli_alert_warning("cmake is required for building from source")
    if (grepl("darwin", R.version$os)) {
      cli::cli_alert_info("Install with: brew install cmake")
    } else {
      cli::cli_alert_info("Install cmake for your Linux distribution")
    }
  }

  # Check for SDK version mismatch (macOS)
  if (grepl("darwin", R.version$os) && !is.null(report$torch_libcxx_version)) {
    torch_version <- as.numeric(gsub("\\..*", "", report$torch_libcxx_version))

    # torch libc++ version 1700.x = macOS 13/14 SDK
    # Current SDK 26.x = newer SDK with libc++ 2000.x
    if (torch_version < 2000) {
      sdk_info <- if (!is.null(report$current_sdk)) report$current_sdk else "unknown"
      if (grepl("26\\.|MacOSX26", sdk_info) || grepl("15\\.", sdk_info)) {
        warnings_found <- TRUE
        cli::cli_alert_warning("SDK version mismatch detected!")
        cli::cli_alert_info("torch was built with libc++ version {report$torch_libcxx_version}")
        cli::cli_alert_info("Current SDK likely uses libc++ 2000.x (incompatible!)")
        cli::cli_alert_info("This causes ABI incompatibility even with the same compiler")
        cli::cli_alert_info("")
        cli::cli_alert_info("The build script will automatically use macOS 15.4 SDK")
        cli::cli_alert_info("Run: ./tools/build_and_install.sh")
        report$sdk_mismatch <- TRUE
      }
    }
  }

  # Check for non-system compiler (potential ABI mismatch risk)
  if (!is.null(report$makevars_content) && length(report$makevars_content) > 0) {
    # Check if using a non-system compiler
    cxx_lines <- grep("^CXX[^F]*=", report$makevars_content, value = TRUE)
    if (length(cxx_lines) > 0) {
      for (line in cxx_lines) {
        parts <- strsplit(line, "=")[[1]]
        if (length(parts) >= 2) {
          compiler_path <- trimws(strsplit(trimws(parts[2]), " ")[[1]][1])

          # Check if it's not the system compiler
          if (grepl("/opt/", compiler_path) || grepl("/usr/local/", compiler_path) ||
              grepl("homebrew", compiler_path) || grepl("Cellar", compiler_path)) {
            warnings_found <- TRUE
            cli::cli_alert_warning("Using non-system compiler: {compiler_path}")
            cli::cli_alert_warning("This may cause ABI incompatibility with torch!")
            cli::cli_alert_info("torch is typically built with Apple's system clang (/usr/bin/clang++)")
            cli::cli_alert_info("The build script will automatically use system compiler")
            cli::cli_alert_info("Run: ./tools/build_and_install.sh")
            report$abi_warning <- TRUE
          }
        }
      }
    }
  }

  if (!issues_found && !warnings_found) {
    cli::cli_alert_success("No build configuration issues detected")
  }

  # Runtime test
  cli::cli_h2("Runtime Test")

  if (tvl_installed && torch_installed && torch::torch_is_installed()) {
    cli::cli_alert_info("Testing basic functionality...")
    runtime_ok <- tryCatch({
      # Simple test: create small tensors and call ops_nms
      boxes <- torch::torch_tensor(matrix(c(0, 0, 1, 1), nrow = 1))
      scores <- torch::torch_tensor(c(1.0))
      result <- ops_nms(boxes, scores, 0.5)
      TRUE
    }, error = function(e) {
      report$runtime_error <<- conditionMessage(e)
      FALSE
    })

    if (runtime_ok) {
      cli::cli_alert_success("Runtime test PASSED")
      report$runtime_test <- "passed"
    } else {
      cli::cli_alert_danger("Runtime test FAILED: {report$runtime_error}")
      cli::cli_alert_warning("This suggests an ABI mismatch or linking issue")
      if (!is.null(report$abi_warning) && report$abi_warning) {
        cli::cli_alert_info("This is likely caused by the non-system compiler in Makevars")
        cli::cli_alert_info("Follow the recommendations above to fix")
      }
      report$runtime_test <- "failed"
    }
  } else {
    cli::cli_alert_info("Skipping runtime test (dependencies not ready)")
    report$runtime_test <- "skipped"
  }

  # Overall status
  cli::cli_h2("Overall Status")

  all_ok <- torch_installed &&
            torch::torch_is_installed() &&
            tvl_installed &&
            (is.null(report$runtime_test) || report$runtime_test != "failed")

  if (all_ok) {
    cli::cli_alert_success("torchvisionlib is ready to use!")
  } else {
    cli::cli_alert_danger("torchvisionlib is NOT ready to use")

    if (!torch_installed) {
      cli::cli_alert_info("1. Install torch: install.packages('torch')")
    } else if (!torch::torch_is_installed()) {
      cli::cli_alert_info("1. Install LibTorch: torch::install_torch()")
    }

    if (!tvl_installed) {
      step_num <- if (!torch_installed || !torch::torch_is_installed()) "2" else "1"
      cli::cli_alert_info("{step_num}. Install torchvisionlib binaries: torchvisionlib::install_torchvisionlib()")
    }
  }

  report$ready <- all_ok

  invisible(report)
}

# Helper function to format file size
format_file_size <- function(path) {
  if (!file.exists(path)) return("N/A")

  size <- file.info(path)$size
  if (is.na(size)) return("N/A")

  units <- c("B", "KB", "MB", "GB")
  unit_idx <- 1

  while (size > 1024 && unit_idx < length(units)) {
    size <- size / 1024
    unit_idx <- unit_idx + 1
  }

  sprintf("%.1f %s", size, units[unit_idx])
}
