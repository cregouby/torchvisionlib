## usethis namespace: start
#' @useDynLib torchvisionlib, .registration = TRUE
#' @importFrom Rcpp sourceCpp
#' @importFrom utils download.file packageDescription unzip
## usethis namespace: end
NULL

# Store original LD_LIBRARY_PATH for potential cleanup
.original_ld_library_path <- NULL

#' Set library search paths at runtime
#'
#' This sets LD_LIBRARY_PATH (Linux) or DYLD_FALLBACK_LIBRARY_PATH (macOS)
#' to ensure the dynamic linker can find our dependent libraries.
#'
#' @keywords internal
.set_library_search_path <- function() {
  pkg_libs <- system.file("libs", package = "torchvisionlib")
  torch_libs <- tryCatch(
    system.file("lib", package = "torch"),
    error = function(e) ""
  )

  paths <- character(0)
  if (nzchar(pkg_libs) && dir.exists(pkg_libs)) {
    paths <- c(paths, pkg_libs)
  }
  if (nzchar(torch_libs) && dir.exists(torch_libs)) {
    paths <- c(paths, torch_libs)
  }

  if (length(paths) == 0) return(invisible(FALSE))

  new_paths <- paste(paths, collapse = ":")

  # Set for Linux
  current <- Sys.getenv("LD_LIBRARY_PATH")
  if (!nzchar(current) || !any(sapply(paths, function(p) grepl(p, current, fixed = TRUE)))) {
    .original_ld_library_path <<- current
    if (nzchar(current)) {
      Sys.setenv(LD_LIBRARY_PATH = paste(new_paths, current, sep = ":"))
    } else {
      Sys.setenv(LD_LIBRARY_PATH = new_paths)
    }
  }

  # Set for macOS
  if (Sys.info()["sysname"] == "Darwin") {
    current_dyld <- Sys.getenv("DYLD_FALLBACK_LIBRARY_PATH")
    if (!nzchar(current_dyld) || !any(sapply(paths, function(p) grepl(p, current_dyld, fixed = TRUE)))) {
      if (nzchar(current_dyld)) {
        Sys.setenv(DYLD_FALLBACK_LIBRARY_PATH = paste(new_paths, current_dyld, sep = ":"))
      } else {
        Sys.setenv(DYLD_FALLBACK_LIBRARY_PATH = new_paths)
      }
    }
  }

  invisible(TRUE)
}

.onLoad <- function(lib, pkg) {
  # Set library search paths FIRST (before any library loading)
  .set_library_search_path()

  torch_available <- tryCatch({
    requireNamespace("torch", quietly = TRUE) &&
      torch::torch_is_installed()
  }, error = function(e) FALSE)

  if (!torch_available) {
    stop("Note: torch package detection returned FALSE")
  }

  if (!torchvisionlib_is_installed())
    install_torchvisionlib()

  if (!torchvisionlib_is_installed()) {
    if (interactive())
      warning("torchvisionlib is not installed. Run `install_torchvisionlib()` before using the package.")
  } else {
    if (grepl("mingw", R.version[["os"]])) {
      lib_file <- lib_path("torchvisionlib")
      withr::with_dir(dirname(lib_file), {
        dyn.load(basename(lib_file), local = FALSE)
      })
    } else {
      # On Unix, load dependencies first if they exist as separate files
      tv_path <- lib_path("torchvision")
      if (file.exists(tv_path)) {
        dyn.load(tv_path, local = FALSE)
      }
      # Then load the main package library
      dyn.load(lib_path("torchvisionlib"), local = FALSE)
    }

    # when using devtools::load_all() the library might be available in
    # `lib/pkg/src`
    pkgload <- file.path(lib, pkg, "src", paste0(pkg, .Platform$dynlib.ext))
    if (file.exists(pkgload))
      dyn.load(pkgload)
    else
      library.dynam("torchvisionlib", pkg, lib)
  }
}

inst_path <- function() {
  install_path <- Sys.getenv("TORCHVISIONLIB_HOME")
  if (nzchar(install_path)) return(install_path)

  system.file("", package = "torchvisionlib")
}

lib_path <- function(name = "torchvisionlib") {
  install_path <- inst_path()
  ext <- lib_ext()

  # R convention: shared libraries go in 'libs/' on all platforms
  lib_dir <- file.path(install_path, "libs")

  # On Unix, R may use lib64/ for 64-bit libs, but for packages we stick to libs/
  if (.Platform$OS.type == "unix" && !dir.exists(lib_dir)) {
    # Fallback for edge cases
    if (dir.exists(file.path(install_path, "lib64"))) {
      lib_dir <- file.path(install_path, "lib64")
    } else if (dir.exists(file.path(install_path, "lib"))) {
      lib_dir <- file.path(install_path, "lib")
    }
  }

  # Windows uses bin/ for DLLs
  if (.Platform$OS.type == "windows") {
    lib_dir <- file.path(install_path, "bin")
  }

  # Build the filename: R adds 'lib' prefix on Unix automatically for system libs,
  # but for package libs we use the exact name (e.g., "torchvisionlib.so")
  if (.Platform$OS.type == "unix") {
    # we expect files named exactly as target: libtorchvisionlib.so
    file.path(lib_dir, paste0("lib", name, ext))
  } else {
    file.path(lib_dir, paste0(name, ext))
  }
}


lib_ext <- function() {
  if (grepl("darwin", version$os))
    ".dylib"
  else if (grepl("linux", version$os))
    ".so"
  else
    ".dll"
}

#' Checks if an installation of torchvisionlib was found.
#' @rdname install_torchvisionlib
#' @export
torchvisionlib_is_installed <- function() {
  file.exists(lib_path("torchvisionlib"))
}

#' Install additional libraries
#'
#' @param url Url for the binaries. Can also be the file path to the binaries.
#'
#' @export
install_torchvisionlib <- function(url = Sys.getenv("TORCHVISIONLIB_URL", unset = NA)) {

  if (!interactive() && Sys.getenv("TORCH_INSTALL", unset = 0) == "0") return()

  if (is.na(url)) {
    tmp <- tempfile(fileext = ".zip")
    version <- packageDescription("torchvisionlib")$Version
    os <- get_cmake_style_os()
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
    url <- sprintf("https://github.com/mlverse/torchvisionlib/releases/download/v%s/torchvisionlib-%s+%s-%s.zip",
                   version, version, dev, os)
  }

  if (is_url(url)) {
    file <- tempfile(fileext = ".zip")
    on.exit(unlink(file), add = TRUE)
    download.file(url = url, destfile = file)
  } else {
    message('Using file ', url)
    file <- url
  }

  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  unzip(file, exdir = tmp)

  file.copy(
    list.files(list.files(tmp, full.names = TRUE), full.names = TRUE),
    inst_path(),
    recursive = TRUE
  )
}

get_cmake_style_os <- function() {
  os <- version$os
  if (grepl("darwin", os)) {
    "Darwin"
  } else if (grepl("linux", os)) {
    "Linux"
  } else {
    "win64"
  }
}

is_url <- function(x) {
  grepl("^https", x) || grepl("^http", x)
}

