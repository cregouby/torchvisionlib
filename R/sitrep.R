#' @title torchvisionlib Situation Report
#' @description Comprehensive diagnostic function for torchvisionlib build and installation status.
#'   Dumps everything relevant in one go to diagnose setup issues.
#' @return Invisibly returns a list with diagnostic results.
#' @export
#' @examples
#' if (FALSE) {
#'   torchvisionlib_sitrep()
#' }
torchvisionlib_sitrep <- function() {

  # Helper functions
  # =========================================================================

  # Check if a system command exists
  cmd_exists <- function(cmd) {
    tryCatch({
      suppressWarnings(system2(cmd, stdout = TRUE, stderr = TRUE))
      TRUE
    }, error = function(e) FALSE)
  }

  # Get first line of command output
  cmd_output <- function(cmd, args = character()) {
    tryCatch({
      out <- suppressWarnings(system2(cmd, args, stdout = TRUE, stderr = TRUE))
      if (length(out) > 0) out[1] else NA_character_
    }, error = function(e) NA_character_)
  }

  # Format file size
  fmt_size <- function(bytes) {
    if (is.null(bytes) || is.na(bytes)) return("unknown")
    structure(bytes, class = "object_size") |> format("MB")
  }

  # Track issues
  issues <- list(critical = 0, warning = 0)
  track_issue <- function(type) {
    if (type == "critical") issues$critical <<- issues$critical + 1
    else if (type == "warning") issues$warning <<- issues$warning + 1
  }

  # Initialize result storage
  # =========================================================================
  result <- new.env(parent = emptyenv())
  result$timestamp <- Sys.time()

  # Section 1: System Information
  # =========================================================================
  cli::cli_h1("torchvisionlib Situation Report")
  cli::cli_text("Generated: {Sys.time()}")
  cli::cli_text("")

  cli::cli_h2("System Information")

  os <- Sys.info()["sysname"]
  machine <- Sys.info()["machine"]
  r_ver <- R.version.string
  r_home <- R.home()

  cli::cli_ul(c(
    paste("OS:", os),
    paste("Machine:", machine),
    paste("R version:", r_ver),
    paste("R home:", r_home),
    paste("Working directory:", getwd())
  ))

  result$platform <- list(
    os = unname(os),
    machine = unname(machine),
    r_version = r_ver,
    r_home = r_home
  )

  # CPU cores
  nproc <- NA_integer_
  if (os == "Linux") {
    nproc <- tryCatch(
      as.integer(cmd_output("nproc")),
      error = function(e) NA_integer_
    )
  } else if (os == "Darwin") {
    nproc <- tryCatch(
      as.integer(cmd_output("sysctl", c("-n", "hw.ncpu"))),
      error = function(e) NA_integer_
    )
  }
  cli::cli_li(paste("CPU cores:", if (is.na(nproc)) "unknown" else nproc))
  result$platform$nproc <- nproc

  # Disk space
  disk_info <- "unknown"
  if (os == "Linux" || os == "Darwin") {
    df_out <- tryCatch(
      cmd_output("df", c("-h", ".")),
      error = function(e) NA_character_
    )
    if (!is.na(df_out)) {
      disk_info <- df_out
    }
  }
  cli::cli_li(paste("Disk space:", disk_info))
  cli::cli_text("")

  # Section 2: Git & Torchvision Source
  # =========================================================================
  cli::cli_h2("Git & Torchvision Source")

  result$git <- list()
  result$source <- list()

  # Git installed?
  git_ok <- cmd_exists("git")
  if (!git_ok) {
    cli::cli_li("{cli::col_red('\u2716')} git: NOT INSTALLED")
    track_issue("critical")
    result$git$installed <- FALSE
  } else {
    git_ver <- cmd_output("git", c("--version"))
    cli::cli_li("{cli::col_green('\u2714')} git: {git_ver}")
    result$git$installed <- TRUE
    result$git$version <- git_ver
  }

  # GitHub reachable? (only if git exists)
  github_ok <- FALSE
  if (git_ok) {
    github_ok <- tryCatch({
      suppressWarnings(
        system2("git", c("ls-remote", "https://github.com/pytorch/vision", "HEAD"),
                stdout = TRUE, stderr = TRUE, timeout = 10)
      )
      TRUE
    }, error = function(e) FALSE, warning = function(w) FALSE)

    if (github_ok) {
      cli::cli_li("{cli::col_green('\u2714')} GitHub connectivity: reachable")
    } else {
      cli::cli_li("{cli::col_red('\u2716')} GitHub connectivity: FAILED (check network)")
      track_issue("critical")
    }
  }
  result$source$github_reachable <- github_ok

  # Cache directory
  cache_dir <- path.expand("~/.cache/torchvision")
  cache_exists <- dir.exists(cache_dir)

  if (cache_exists) {
    cli::cli_li("{cli::col_green('\u2714')} Cache directory: {cache_dir}")
    result$source$cache_dir <- cache_dir
    result$source$cache_exists <- TRUE

    # Is it a valid git repo?
    git_dir <- file.path(cache_dir, ".git")
    if (dir.exists(git_dir)) {
      cli::cli_li("{cli::col_green('\u2714')} Torchvision cached: YES")
      result$source$torchvision_cached <- TRUE

      # What version?
      if (git_ok) {
        tag <- tryCatch({
          cmd_output("git", c("-C", cache_dir, "describe", "--tags"))
        }, error = function(e) "unknown")
        cli::cli_li("  Version: {tag}")
        result$source$torchvision_version <- tag
      }
    } else {
      cli::cli_li("{cli::col_yellow('!')} Cache exists but not a git repo (corrupted?)")
      track_issue("warning")
      result$source$torchvision_cached <- FALSE
    }
  } else {
    cli::cli_li("{cli::col_yellow('!')} Cache directory: NOT FOUND (will be created on build)")
    result$source$cache_exists <- FALSE
    result$source$torchvision_cached <- FALSE
  }
  cli::cli_text("")

  # Section 3: Torch Installation
  # =========================================================================
  cli::cli_h2("Torch Installation")

  result$torch <- list()

  # torch package installed?
  torch_installed <- requireNamespace("torch", quietly = TRUE)
  if (!torch_installed) {
    cli::cli_li("{cli::col_red('\u2716')} {.pkg torch} package: NOT INSTALLED")
    cli::cli_li("  Fix: {.fn install.packages('torch'); torch::install_torch()}")
    track_issue("critical")
    result$torch$installed <- FALSE
  } else {
    torch_ver <- as.character(packageVersion("torch"))
    cli::cli_li("{cli::col_green('\u2714')} {.pkg torch} package: v{torch_ver}")
    result$torch$installed <- TRUE
    result$torch$version <- torch_ver

    # torch_install_path()
    torch_path <- tryCatch(
      torch::torch_install_path(),
      error = function(e) NULL
    )
    if (is.null(torch_path) || torch_path == "") {
      cli::cli_li("{cli::col_red('\u2716')} torch_install_path(): NOT SET")
      cli::cli_li("  Fix: Run {.fn torch::install_torch()}")
      track_issue("critical")
      result$torch$install_path <- NULL
    } else {
      cli::cli_li("{cli::col_green('\u2714')} Torch path: {.file torch_path}")
      result$torch$install_path <- torch_path
    }

    # lib directory
    torch_lib <- system.file("lib", package = "torch")
    if (torch_lib == "" || !dir.exists(torch_lib)) {
      cli::cli_li("{cli::col_red('\u2716')} Torch lib directory: NOT FOUND")
      cli::cli_li("  Fix: Run {.fn torch::install_torch()}")
      track_issue("critical")
      result$torch$lib_path <- NULL
    } else {
      cli::cli_li("{cli::col_green('\u2714')} Torch lib: {.field {torch_lib}}")
      result$torch$lib_path <- torch_lib

      # Count libraries
      lib_ext_pattern <- if (os == "Darwin") "\\.dylib$" else "\\.so$"
      lib_files <- list.files(torch_lib, pattern = lib_ext_pattern)
      cli::cli_li("  Libraries found: {length(lib_files)}")
      result$torch$lib_count <- length(lib_files)
    }

    # include directory
    torch_inc <- system.file("include", package = "torch")
    if (torch_inc == "" || !dir.exists(torch_inc)) {
      cli::cli_li("{cli::col_red('\u2716')} Torch include: NOT FOUND")
      cli::cli_li("  Fix: Run {.fn torch::install_torch()}")
      track_issue("critical")
      result$torch$include_path <- NULL
    } else {
      cli::cli_li("{cli::col_green('\u2714')} Torch include: {.file torch_inc}")
      result$torch$include_path <- torch_inc
    }

    # CUDA available?
    cuda_available <- tryCatch(
      torch::cuda_is_available(),
      error = function(e) FALSE
    )
    if (cuda_available) {
      cli::cli_li("{cli::col_green('\u2714')} CUDA: available")
      result$torch$cuda <- TRUE

      # CUDA version
      cuda_ver <- tryCatch(
        torch::cuda_version(),
        error = function(e) NULL
      )
      if (!is.null(cuda_ver)) {
        cli::cli_li("  CUDA version: {cuda_ver}")
        result$torch$cuda_version <- as.character(cuda_ver)
      }
    } else {
      cli::cli_li("{cli::col_yellow('!')} CUDA: not available (CPU-only build)")
      result$torch$cuda <- FALSE
    }
  }
  cli::cli_text("")

  # Section 4: Build Tools
  # =========================================================================
  cli::cli_h2("Build Tools")

  result$build <- list()

  # CMake
  cmake_ok <- cmd_exists("cmake")
  if (!cmake_ok) {
    cli::cli_li("{cli::col_red('\u2716')} {.field cmake}: NOT INSTALLED")
    if (os == "Linux") {
      cli::cli_li("  Fix: {.fn apt install cmake (or yum install cmake)}")
    } else if (os == "Darwin") {
      cli::cli_li("  Fix: {.fn brew install cmake}")
    }
    track_issue("critical")
    result$build$cmake <- FALSE
  } else {
    cmake_ver <- cmd_output("cmake", c("--version"))
    cli::cli_li("{cli::col_green('\u2714')} {.field cmake}: {cmake_ver}")
    result$build$cmake <- TRUE
    result$build$cmake_version <- cmake_ver
  }

  # C++ compiler
  cxx_name <- NA_character_
  cxx_ver <- NA_character_

  # Try g++ first
  if (cmd_exists("g++")) {
    cxx_out <- cmd_output("g++", c("--version"))
    cxx_name <- "g++"
    cxx_ver <- cxx_out
  } else if (cmd_exists("clang++")) {
    # Try clang++
    cxx_out <- cmd_output("clang++", c("--version"))
    cxx_name <- "clang++"
    cxx_ver <- cxx_out
  }

  if (is.na(cxx_name)) {
    cli::cli_li("{cli::col_red('\u2716')} C++ compiler: NOT FOUND")
    if (os == "Linux") {
      cli::cli_li("  Fix: {.fn apt install g++ (or yum install gcc-c++)}")
    } else if (os == "Darwin") {
      cli::cli_li("  Fix: {.fn xcode-select --install}")
    }
    track_issue("critical")
    result$build$compiler <- FALSE
  } else {
    cli::cli_li("{cli::col_green('\u2714')} C++ compiler: {.field {cxx_name}}")
    cli::cli_li("  Version: {cxx_ver}")
    result$build$compiler <- TRUE
    result$build$compiler_name <- cxx_name
    result$build$compiler_version <- cxx_ver
  }

  # Find package root (csrc location)
  pkg_root <- tryCatch(
    getwd(),  # Simple: use current directory
    error = function(e) getwd()
  )

  # Check for DESCRIPTION to confirm package root
  desc_file <- file.path(pkg_root, "DESCRIPTION")
  if (!file.exists(desc_file)) {
    # Try parent directory
    if (file.exists(file.path(dirname(pkg_root), "DESCRIPTION"))) {
      pkg_root <- dirname(pkg_root)
    }
  }

  # csrc directory
  csrc_dir <- file.path(pkg_root, "csrc")
  if (dir.exists(csrc_dir)) {
    cli::cli_li("{cli::col_green('\u2714')} {.file csrc/}: exists ({csrc_dir})")
    result$build$csrc_exists <- TRUE

    cmake_file <- file.path(csrc_dir, "CMakeLists.txt")
    if (file.exists(cmake_file)) {
      cli::cli_li("{cli::col_green('\u2714')} {.file CMakeLists.txt}: exists")
      result$build$cmakelists_exists <- TRUE
    } else {
      cli::cli_li("{cli::col_red('\u2716')} {.file CMakeLists.txt}: MISSING")
      track_issue("critical")
      result$build$cmakelists_exists <- FALSE
    }
  } else {
    cli::cli_li("{cli::col_yellow('!')} {.file csrc/}: not found (not in package source directory?)")
    result$build$csrc_exists <- FALSE
  }

  # inst directory
  inst_dir <- file.path(pkg_root, "inst")
  if (dir.exists(inst_dir)) {
    cli::cli_li("{cli::col_green('\u2714')} {.file inst/}: exists")
    result$build$inst_exists <- TRUE
  } else {
    cli::cli_li("{cli::col_yellow('!')} {.file inst/}: not found")
    result$build$inst_exists <- FALSE
  }
  cli::cli_text("")

  # Section 5: RPATH Tools
  # =========================================================================
  cli::cli_h2("RPATH Tools")

  result$rpath <- list()

  if (os == "Linux") {
    # patchelf
    patchelf_ok <- cmd_exists("patchelf")
    if (!patchelf_ok) {
      cli::cli_li("{cli::col_red('\u2716')} {.field patchelf}: NOT INSTALLED")
      cli::cli_li("  Fix: {.fn apt install patchelf (or yum install patchelf)}")
      track_issue("critical")
      result$rpath$patchelf <- FALSE
    } else {
      cli::cli_li("{cli::col_green('\u2714')} {.field patchelf}: installed")
      result$rpath$patchelf <- TRUE
    }
  } else if (os == "Darwin") {
    # install_name_tool (part of Xcode CLI)
    int_ok <- cmd_exists("install_name_tool")
    if (!int_ok) {
      cli::cli_li("{cli::col_red('\u2716')} {.field install_name_tool}: NOT INSTALLED")
      cli::cli_li("  Fix: {.fn xcode-select --install}")
      track_issue("critical")
      result$rpath$install_name_tool <- FALSE
    } else {
      cli::cli_li("{cli::col_green('\u2714')} {.field install_name_tool}: available")
      result$rpath$install_name_tool <- TRUE
    }

    # otool
    otool_ok <- cmd_exists("otool")
    if (otool_ok) {
      cli::cli_li("{cli::col_green('\u2714')} {.field otool}: available")
      result$rpath$otool <- TRUE
    } else {
      cli::cli_li("{cli::col_yellow('!')} {.field otool}: not available")
      result$rpath$otool <- FALSE
    }
  }

  # LD_LIBRARY_PATH
  ld_path <- Sys.getenv("LD_LIBRARY_PATH")
  if (ld_path == "") {
    cli::cli_li("{cli::col_yellow('!')} {.envvar LD_LIBRARY_PATH}: not set")
    result$rpath$ld_library_path <- NULL
  } else {
    cli::cli_li("{cli::col_green('\u2714')} {.envvar LD_LIBRARY_PATH}: set")
    cli::cli_li("  {.file {ld_path}}")
    result$rpath$ld_library_path <- ld_path
  }

  # DYLD_FALLBACK_LIBRARY_PATH (macOS)
  if (os == "Darwin") {
    dyld_path <- Sys.getenv("DYLD_FALLBACK_LIBRARY_PATH")
    if (dyld_path == "") {
      cli::cli_li("{cli::col_yellow('!')} {.envvar DYLD_FALLBACK_LIBRARY_PATH}: not set")
      result$rpath$dyld_fallback_library_path <- NULL
    } else {
      cli::cli_li("{cli::col_green('\u2714')} {.envvar DYLD_FALLBACK_LIBRARY_PATH}: set")
      cli::cli_li("  {.file {dyld_path}}")
      result$rpath$dyld_fallback_library_path <- dyld_path
    }
  }
  cli::cli_text("")

  # Section 6: R Documentation Tools
  # =========================================================================
  cli::cli_h2("R Documentation Tools")

  result$docs <- list()

  # Rcpp
  rcpp_ok <- requireNamespace("Rcpp", quietly = TRUE)
  if (!rcpp_ok) {
    cli::cli_li("{cli::col_red('\u2716')} {.pkg Rcpp}: NOT INSTALLED")
    cli::cli_li("  Fix: {.fn install.packages('Rcpp')}")
    track_issue("critical")
    result$docs$rcpp <- FALSE
  } else {
    rcpp_ver <- as.character(packageVersion("Rcpp"))
    cli::cli_li("{cli::col_green('\u2714')} {.pkg Rcpp}: v{rcpp_ver}")
    result$docs$rcpp <- TRUE
    result$docs$rcpp_version <- rcpp_ver
  }

  # roxygen2
  roxy_ok <- requireNamespace("roxygen2", quietly = TRUE)
  if (!roxy_ok) {
    cli::cli_li("{cli::col_yellow('!')} {.pkg roxygen2}: NOT INSTALLED")
    cli::cli_li("  Fix: {.fn install.packages('roxygen2')}")
    track_issue("warning")
    result$docs$roxygen2 <- FALSE
  } else {
    roxy_ver <- as.character(packageVersion("roxygen2"))
    cli::cli_li("{cli::col_green('\u2714')} {.pkg roxygen2}: v{roxy_ver}")
    result$docs$roxygen2 <- TRUE
    result$docs$roxygen2_version <- roxy_ver
  }

  # torchexport (optional, may not be on CRAN)
  te_ok <- requireNamespace("torchexport", quietly = TRUE)
  if (!te_ok) {
    cli::cli_li("{cli::col_yellow('!')} {.pkg torchexport}: NOT INSTALLED (optional)")
    result$docs$torchexport <- FALSE
  } else {
    cli::cli_li("{cli::col_green('\u2714')} {.pkg torchexport}: available")
    result$docs$torchexport <- TRUE
  }

  # sed (for NAMESPACE fix)
  sed_ok <- cmd_exists("sed")
  if (!sed_ok) {
    cli::cli_li("{cli::col_yellow('!')} {.field sed}: NOT FOUND")
    result$docs$sed <- FALSE
  } else {
    cli::cli_li("{cli::col_green('\u2714')} {.field sed}: available")
    result$docs$sed <- TRUE
  }
  cli::cli_text("")

  # Section 7: Built Libraries
  # =========================================================================
  cli::cli_h2("Built Libraries")

  result$libraries <- list()

  lib_ext <- if (os == "Darwin") "dylib" else "so"
  inst_libs <- file.path(pkg_root, "inst", "libs")

  if (!dir.exists(inst_libs)) {
    cli::cli_li("{cli::col_yellow('!')} {.file inst/libs/}: not found (not built yet?)")
    result$libraries$inst_libs_exists <- FALSE
  } else {
    cli::cli_li("{cli::col_green('\u2714')} {.file inst/libs/}: exists")
    result$libraries$inst_libs_exists <- TRUE

    # libtorchvision
    lib_tv_name <- paste0("libtorchvision.", lib_ext)
    lib_tv <- file.path(inst_libs, lib_tv_name)

    if (file.exists(lib_tv)) {
      size_tv <- file.info(lib_tv)$size
      cli::cli_li("{cli::col_green('\u2714')} {.field {lib_tv_name}}: {fmt_size(size_tv)}")
      result$libraries$libtorchvision <- list(
        exists = TRUE,
        path = lib_tv,
        size = size_tv
      )

      # Check dependencies (Linux: ldd, macOS: otool)
      if (os == "Linux" && cmd_exists("ldd")) {
        ldd_out <- tryCatch(
          suppressWarnings(system2("ldd", lib_tv, stdout = TRUE, stderr = TRUE)),
          error = function(e) character()
        )
        missing_deps <- grep("not found", ldd_out, value = TRUE)
        if (length(missing_deps) > 0) {
          cli::cli_li("{cli::col_red('\u2716')}  Missing dependencies: {length(missing_deps)}")
          for (m in head(missing_deps, 3)) {
            cli::cli_li("    {.field {m}}")
          }
          if (length(missing_deps) > 3) {
            cli::cli_li("    ... and {length(missing_deps) - 3} more")
          }
          track_issue("critical")
          result$libraries$libtorchvision$missing_deps <- missing_deps
        } else {
          cli::cli_li("{cli::col_green('\u2714')}  Dependencies: OK")
          result$libraries$libtorchvision$missing_deps <- character()
        }
      } else if (os == "Darwin" && cmd_exists("otool")) {
        otool_out <- tryCatch(
          suppressWarnings(system2("otool", c("-L", lib_tv), stdout = TRUE, stderr = TRUE)),
          error = function(e) character()
        )
        cli::cli_li("{cli::col_green('\u2714')}  Linked libraries: {length(otool_out)}")
        result$libraries$libtorchvision$linked_libs <- otool_out
      }
    } else {
      cli::cli_li("{cli::col_red('\u2716')} {.field {lib_tv_name}}: MISSING")
      track_issue("critical")
      result$libraries$libtorchvision <- list(exists = FALSE)
    }

    # libtorchvisionlib
    lib_tvl_name <- paste0("libtorchvisionlib.", lib_ext)
    lib_tvl <- file.path(inst_libs, lib_tvl_name)

    if (file.exists(lib_tvl)) {
      size_tvl <- file.info(lib_tvl)$size
      cli::cli_li("{cli::col_green('\u2714')} {.field {lib_tv_name}}: {fmt_size(size_tvl)}")
      result$libraries$libtorchvisionlib <- list(
        exists = TRUE,
        path = lib_tvl,
        size = size_tvl
      )

      # Check dependencies
      if (os == "Linux" && cmd_exists("ldd")) {
        ldd_out <- tryCatch(
          suppressWarnings(system2("ldd", lib_tvl, stdout = TRUE, stderr = TRUE)),
          error = function(e) character()
        )
        missing_deps <- grep("not found", ldd_out, value = TRUE)
        if (length(missing_deps) > 0) {
          cli::cli_li("{cli::col_red('\u2716')}  Missing dependencies: {length(missing_deps)}")
          for (m in head(missing_deps, 3)) {
            cli::cli_li("    {m}")
          }
          track_issue("critical")
          result$libraries$libtorchvisionlib$missing_deps <- missing_deps
        } else {
          cli::cli_li("{cli::col_green('\u2714')}  Dependencies: OK")
          result$libraries$libtorchvisionlib$missing_deps <- character()
        }
      }
    } else {
      cli::cli_li("{cli::col_red('\u2716')} {.field {lib_tvl_name}}: MISSING")
      track_issue("critical")
      result$libraries$libtorchvisionlib <- list(exists = FALSE)
    }

    # List all .so/.dylib files
    all_libs <- list.files(inst_libs, pattern = paste0("\\.", lib_ext, "$"))
    if (length(all_libs) > 0) {
      cli::cli_li("All libraries in {.file inst/libs/}: {.field {paste(all_libs, collapse = ', ')}}")
      result$libraries$all_files <- all_libs
    }
  }
  cli::cli_text("")

  # Section 8: Package Installation
  # =========================================================================
  cli::cli_h2("Package Installation")

  result$installation <- list()

  # Is package installed?
  tvl_installed <- torchvisionlib_is_installed()
  if (!tvl_installed) {
    cli::cli_li("{cli::col_yellow('!')} {.pkg torchvisionlib}: NOT INSTALLED")
    cli::cli_li("  Run: {.fn R CMD INSTALL {pkg_root}}")
    result$installation$installed <- FALSE
    result$installation$loadable <- FALSE
  } else {
    tvl_ver <- as.character(packageVersion("torchvisionlib"))
    cli::cli_li("{cli::col_green('\u2714')} {.pkg torchvisionlib}: v{tvl_ver}")
    result$installation$installed <- TRUE
    result$installation$version <- tvl_ver

    # Where installed?
    tvl_path <- system.file("", package = "torchvisionlib")
    cli::cli_li("  Installed at: {.file {tvl_path}}")
    result$installation$path <- tvl_path

    # Libraries in installed location
    tvl_libs_dir <- file.path(tvl_path, "libs")
    if (dir.exists(tvl_libs_dir)) {
      tvl_lib_files <- list.files(tvl_libs_dir, pattern = "\\.(so|dylib|dll)$")
      if (length(tvl_lib_files) > 0) {
        cli::cli_li("  Installed libraries:{.field {paste(tvl_lib_files, collapse = ', ')}}")
        result$installation$lib_files <- tvl_lib_files
      }
    }

    # Check for torch version compatibility BEFORE attempting load
    # The duplicate operator error happens when torchvisionlib was built
    # against a different torch/LibTorch version
    if (torch_installed && !is.null(result$torch$version)) {
      # Check if torch was loaded BEFORE torchvisionlib
      torch_loaded <- "torch" %in% loadedNamespaces()
      cli::cli_li("  {.pkg torch} loaded before {.pkg torchvisionlib}: {torch_loaded}")
      result$installation$torch_loaded_first <- torch_loaded

      # Check torchvision version used during build (if available)
      tvl_lib_path <- file.path(tvl_path, "libs")
      if (dir.exists(tvl_lib_path)) {
        # Look for version info in library dependencies
        libtv_file <- file.path(tvl_lib_path, "libtorchvision.so")
        if (os == "Darwin") {
          libtv_file <- file.path(tvl_lib_path, "libtorchvision.dylib")
        }

        if (file.exists(libtv_file) && cmd_exists("nm")) {
          # Try to extract version symbols
          nm_out <- tryCatch(
            suppressWarnings(system2("nm", c("-D", libtv_file),
                                     stdout = TRUE, stderr = TRUE)),
            error = function(e) character()
          )
          # Look for version strings
          version_symbols <- grep("version", nm_out, value = TRUE, ignore.case = TRUE)
          if (length(version_symbols) > 0) {
            cli::cli_li("  Build version info found in library")
          }
        }
      }
    }

    # Test load in a SUBPROCESS to avoid crashing the main R session
    # This is critical because duplicate operator registration causes hard crash
    cli::cli_li("Testing package load in isolated subprocess...")

    load_test_code <- sprintf("
      options(error = function(e) {
        cat('LOAD_ERROR:', conditionMessage(e), '\\n')
        quit(status = 1)
      })

      # Set library path if torch lib exists
      torch_lib <- '%s'
      if (torch_lib != '' && dir.exists(torch_lib)) {
        old_ld <- Sys.getenv('LD_LIBRARY_PATH')
        if (old_ld == '') {
          Sys.setenv(LD_LIBRARY_PATH = torch_lib)
        } else {
          Sys.setenv(LD_LIBRARY_PATH = paste(torch_lib, old_ld, sep = ':'))
        }
      }

      # Attempt to load torch first (recommended order)
      if (requireNamespace('torch', quietly = TRUE)) {
        suppressPackageStartupMessages(library(torch))
      }

      # Now try torchvisionlib
      tryCatch({
        suppressPackageStartupMessages(library(torchvisionlib))
        cat('LOAD_SUCCESS\\n')
      }, error = function(e) {
        cat('LOAD_ERROR:', conditionMessage(e), '\\n')
        quit(status = 1)
      })
    ", if (torch_installed && !is.null(result$torch$lib_path)) result$torch$lib_path else "")

    load_result <- tryCatch({
      out <- suppressWarnings(
        system2(
          R.home("bin/R"),
          c("--vanilla", "--slave", "-e", load_test_code),
          stdout = TRUE, stderr = TRUE, timeout = 30
        )
      )
      list(output = out, status = attr(out, "status"))
    }, error = function(e) {
      list(output = e$message, status = 1)
    }, warning = function(w) {
      list(output = w$message, status = 1)
    })

    load_output <- paste(load_result$output, collapse = "\n")

    # Check for specific error patterns
    has_duplicate_op_error <- grepl("Tried to register an operator.*duplicate",
                                    load_output, ignore.case = TRUE)
    has_abort <- grepl("terminate called|Aborted|core dumped",
                       load_output, ignore.case = TRUE)
    has_load_success <- grepl("LOAD_SUCCESS", load_output)

    if (has_load_success && is.null(load_result$status)) {
      cli::cli_li("{cli::col_green('\u2714')} Load test: SUCCESS")
      result$installation$loadable <- TRUE
    } else if (has_duplicate_op_error || has_abort) {
      cli::cli_li("{cli::col_red('\u2716')} Load test: FAILED (duplicate operator registration)")
      track_issue("critical")
      result$installation$loadable <- FALSE
      result$installation$load_error <- "duplicate_operator_registration"

      cli::cli_text("")
      cli::cli_h3("Diagnosis: Duplicate JIT Operator Registration")
      cli::cli_ul(c(
        "This error occurs when torchvisionlib's JIT operators conflict with existing registrations.",
        "Possible causes:",
        "  1. torchvisionlib was built against a different LibTorch version than installed torch",
        "  2. The same operators are already registered by torch or a previously loaded library",
        "  3. torchvision library version mismatch with torch version"
      ))

      cli::cli_text("")
      cli::cli_h3("Suggested Fixes")
      cli::cli_ol(c(
        "Rebuild torchvisionlib: Run tools/build_and_install.sh again after updating torch",
        "Ensure torch version matches: torch::torch_install_path() should match build time",
        "Restart R session: Operators persist in memory between loads",
        "Check torchvision tag: Ensure TORCHVISION_TAG matches torch's LibTorch version"
      ))

      result$installation$diagnosis <- "duplicate_operator_registration"

    } else {
      cli::cli_li("{cli::col_red('\u2716')} Load test: FAILED")
      track_issue("critical")
      result$installation$loadable <- FALSE
      result$installation$load_error <- load_output

      # Show first few lines of error
      error_lines <- head(load_result$output, 5)
      for (line in error_lines) {
        if (nchar(line) > 0) {
          cli::cli_li("  {substr(line, 1, 100)}")
        }
      }
    }
  }
  cli::cli_text("")

  # Section 9: Summary
  # =========================================================================
  cli::cli_h2("Summary")

  # Determine readiness
  ready_build <- git_ok &&
    cmake_ok &&
    !is.na(cxx_name) &&
    torch_installed &&
    result$torch$installed &&
    (!is.null(result$torch$lib_path)) &&
    (!is.null(result$torch$include_path))

  ready_use <- tvl_installed &&
    (isTRUE(result$installation$loadable))

  if (issues$critical > 0) {
    cli::cli_li("{cli::col_red('\u2716')} Critical issues: {issues$critical}")
    cli::cli_li("  Fix the issues above before building/using")
  } else if (issues$warning > 0) {
    cli::cli_li("{cli::col_yellow('!')} Warnings: {issues$warning}")
    cli::cli_li("  Build may work but check warnings above")
  } else {
    cli::cli_li("{cli::col_green('\u2714')} All checks passed")
  }

  cli::cli_text("")

  if (ready_build) {
    cli::cli_li("{cli::col_green('\u2714')} Ready to build: YES")
  } else {
    cli::cli_li("{cli::col_red('\u2716')} Ready to build: NO (fix issues above)")
  }

  if (ready_use) {
    cli::cli_li("{cli::col_green('\u2714')} Ready to use: YES")
  } else {
    cli::cli_li("{cli::col_yellow('!')} Ready to use: NO (install first)")
  }

  # Return invisible result
  # =========================================================================
  result$issues <- as.list(issues)
  result$ready_to_build <- ready_build
  result$ready_to_use <- ready_use

  invisible(as.list(result))
}
