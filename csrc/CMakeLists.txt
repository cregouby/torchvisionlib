cmake_minimum_required(VERSION 3.21)
project(torchvisionlib)

# ------------------------------------------------------------------------------
# Options
# ------------------------------------------------------------------------------
option(USE_LOCAL_TORCHVISION "Use a locally cached torchvision repository" OFF)

include(GNUInstallDirs)

# ------------------------------------------------------------------------------
# Locate LibTorch via the 'torch' R package
# ------------------------------------------------------------------------------
execute_process(
  COMMAND Rscript -e "cat(as.numeric(require(torch, quietly = TRUE)))"
  OUTPUT_VARIABLE TORCH_INSTALLED
  OUTPUT_STRIP_TRAILING_WHITESPACE
)

message(STATUS "TORCH_INSTALLED: ${TORCH_INSTALLED}")

if ("${TORCH_INSTALLED}" STREQUAL "1")
  execute_process(
      COMMAND Rscript -e "cat(torch::torch_install_path())"
      OUTPUT_VARIABLE TORCH_HOME
      OUTPUT_STRIP_TRAILING_WHITESPACE
  )
else()
  # Fallback: install libtorch manually if R package not found
  set(TORCH_INSTALL_SCRIPT "https://raw.githubusercontent.com/mlverse/torch/main/R/install.R")
  set(TORCH_DESCRIPTION "https://raw.githubusercontent.com/mlverse/torch/main/DESCRIPTION")

  execute_process (
    COMMAND Rscript -e "cat(desc::desc(text=readLines('${TORCH_DESCRIPTION}'))\$get('Version'))"
    OUTPUT_VARIABLE TORCH_R_VERSION
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  message(STATUS "TORCH_R_VERSION: ${TORCH_R_VERSION}")
  set(TORCH_HOME "${CMAKE_CURRENT_BINARY_DIR}/torch")
  execute_process(
      COMMAND Rscript -e "Sys.setenv(TORCH_HOME='${TORCH_HOME}', TORCH_R_VERSION='${TORCH_R_VERSION}', TORCH_COMMIT_SHA='none'); source('${TORCH_INSTALL_SCRIPT}'); install_torch();"
  )
endif()

message(STATUS "TORCH_HOME=${TORCH_HOME}")

# ------------------------------------------------------------------------------
# CUDA Configuration
# ------------------------------------------------------------------------------
set(PATCH_CMD "${CMAKE_COMMAND}" -E true) # Default to no-op

if (DEFINED ENV{CUDA} AND NOT "$ENV{CUDA}" STREQUAL "")
  if (WIN32)
    find_package(CUDAToolkit REQUIRED)
  else()
    # Linux/macOS patch for CUDA compatibility
    set(PATCH_CMD git apply "${CMAKE_SOURCE_DIR}/patch/kuint16.patch")
  endif()
  enable_language(CUDA)
endif()

list(APPEND CMAKE_PREFIX_PATH "${TORCH_HOME}")
set(INSTALL_DIR "${CMAKE_CURRENT_BINARY_DIR}/lib/")

include(ExternalProject)

# ------------------------------------------------------------------------------
# Windows dependencies (zlib, libpng, libjpeg)
# ------------------------------------------------------------------------------
if(WIN32)
  set(COMMON_CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR})

  ExternalProject_Add(zlib
    GIT_REPOSITORY https://github.com/madler/zlib.git
    GIT_TAG v1.3.2
    PREFIX "${CMAKE_CURRENT_BINARY_DIR}/zlib"
    CMAKE_ARGS ${COMMON_CMAKE_ARGS} -DCMAKE_ASM_COMPILER=MSVC -DCMAKE_ASM_NASM_COMPILER=MSVC
  )
  ExternalProject_Add(libpng
    GIT_REPOSITORY https://github.com/glennrp/libpng
    GIT_TAG v1.6.55
    DEPENDS zlib
    PREFIX "${CMAKE_CURRENT_BINARY_DIR}/libpng"
    CMAKE_ARGS ${COMMON_CMAKE_ARGS} -DCMAKE_IGNORE_PATH=C:/rtools45/x86_64-w64-mingw32.static.posix/include -DCMAKE_PREFIX_PATH=${CMAKE_PREFIX_PATH}\;${CURRENT_BINARY_DIR}/lib
  )
  ExternalProject_Add(libjpeg
    GIT_REPOSITORY https://github.com/libjpeg-turbo/libjpeg-turbo
    GIT_TAG 3.1.3
    PREFIX "${CMAKE_CURRENT_BINARY_DIR}/libjpeg"
    CMAKE_ARGS ${COMMON_CMAKE_ARGS} -DWITH_JPEG8=0 -DWITH_JPEG7=0 -DENABLE_SHARED=0 -DWITH_TURBOJPEG=0 -DCMAKE_IGNORE_PATH=C:/rtools44/x86_64-w64-mingw32.static.posix/include
  )
endif()

# ------------------------------------------------------------------------------
# Find Torch and Configure TorchVision ExternalProject
# ------------------------------------------------------------------------------
find_package(Torch REQUIRED)

set(TorchVision_DESTDIR "${CMAKE_CURRENT_BINARY_DIR}/lib/")
list(APPEND CMAKE_PREFIX_PATH "${INSTALL_DIR}")

set(TORCHVISION_CMAKE_ARGS
    -DCMAKE_PREFIX_PATH:PATH=${CMAKE_PREFIX_PATH}
    -DCMAKE_INSTALL_PREFIX:PATH=${TorchVision_DESTDIR}
)

if(WIN32)
  list(APPEND TORCHVISION_CMAKE_ARGS -DCMAKE_IGNORE_PREFIX_PATH:PATH=C:/rtools44/x86_64-w64-mingw32.static.posix/)
  if (DEFINED ENV{CUDA} AND NOT "$ENV{CUDA}" STREQUAL "")
    list(APPEND TORCHVISION_CMAKE_ARGS -DWITH_CUDA=ON)
  endif()
elseif(APPLE)
  list(APPEND TORCHVISION_CMAKE_ARGS -DCMAKE_FIND_FRAMEWORK:STRING=LAST)
endif()

if (WIN32)
  set(TORCHVISION_DEPENDS libpng libjpeg)
else()
  set(TORCHVISION_DEPENDS)
endif()

message(STATUS "CMAKE_ARGS: ${TORCHVISION_CMAKE_ARGS}")

# --- Build arguments for ExternalProject_Add dynamically ---
set(TORCHVISION_EP_ARGS
    DEPENDS ${TORCHVISION_DEPENDS}
    CMAKE_CACHE_ARGS ${TORCHVISION_CMAKE_ARGS}
    PREFIX "${CMAKE_CURRENT_BINARY_DIR}/libtorchvision"
    PATCH_COMMAND ${PATCH_CMD}
)

# Handle source logic: Local directory vs Git Clone
if (USE_LOCAL_TORCHVISION AND DEFINED TORCHVISION_SOURCE_DIR)
    if (NOT EXISTS "${TORCHVISION_SOURCE_DIR}")
        message(FATAL_ERROR "TORCHVISION_SOURCE_DIR is set but does not exist: ${TORCHVISION_SOURCE_DIR}")
    endif()

    message(STATUS "Using local torchvision source at ${TORCHVISION_SOURCE_DIR}")
    list(APPEND TORCHVISION_EP_ARGS
        SOURCE_DIR "${TORCHVISION_SOURCE_DIR}"
        DOWNLOAD_COMMAND ""
        UPDATE_COMMAND ""
    )
else()
    message(STATUS "Will clone torchvision from GitHub (default behaviour)")
    list(APPEND TORCHVISION_EP_ARGS
        SOURCE_DIR "${CMAKE_CURRENT_BINARY_DIR}/torchvision-src"
        GIT_REPOSITORY https://github.com/pytorch/vision
        GIT_TAG v0.22.1
        GIT_PROGRESS TRUE
    )
endif()

# Call ExternalProject_Add with the constructed argument list
ExternalProject_Add(TorchVision-project ${TORCHVISION_EP_ARGS})

# ------------------------------------------------------------------------------
# Import TorchVision library targets
# ------------------------------------------------------------------------------
set(TORCHVISION_INCLUDE_DIR "${TorchVision_DESTDIR}/include")
set(TORCHVISION_LIB_DIR "${TorchVision_DESTDIR}/${CMAKE_INSTALL_LIBDIR}")

if(APPLE)
  set(TORCHVISION_LIB_LOCATION "${TORCHVISION_LIB_DIR}/libtorchvision.dylib")
elseif(WIN32)
  set(TORCHVISION_LIB_LOCATION "${TorchVision_DESTDIR}/bin/torchvision.dll")
else()
  set(TORCHVISION_LIB_LOCATION "${TORCHVISION_LIB_DIR}/libtorchvision.so")
endif()

add_library(TorchVision SHARED IMPORTED)
add_library(TorchVision::library ALIAS TorchVision)

set_target_properties(TorchVision PROPERTIES
    IMPORTED_LOCATION "${TORCHVISION_LIB_LOCATION}"
)
if (WIN32)
  set_target_properties(TorchVision PROPERTIES
      IMPORTED_IMPLIB "${TorchVision_DESTDIR}/lib/torchvision.lib"
  )
endif()

# ------------------------------------------------------------------------------
# Build the R package library (torchvisionlib)
# ------------------------------------------------------------------------------
set(TORCHVISION_SRC
    src/torchvisionlib.cpp
    src/ops.cpp
    src/exports.cpp
    src/torchvisionlib_types.cpp
)

add_library(torchvisionlib SHARED ${TORCHVISION_SRC})

target_compile_definitions(torchvisionlib PRIVATE TORCHVISIONLIB_BUILD)
add_library(torchvisionlib::library ALIAS torchvisionlib)

target_include_directories(torchvisionlib PUBLIC
    "${PROJECT_SOURCE_DIR}/include"
    "${TORCH_HOME}/include"
    "${TORCHVISION_INCLUDE_DIR}"
)

set(TORCHVISIONLIB_HEADERS
    include/torchvisionlib/torchvisionlib.h
    include/torchvisionlib/exports.h
    include/torchvisionlib/torchvisionlib_types.h
)
set_property(TARGET torchvisionlib
 PROPERTY PUBLIC_HEADER ${TORCHVISIONLIB_HEADERS}
)

add_dependencies(torchvisionlib TorchVision-project)

# Generate export code for Rcpp
add_custom_target(torchvisionlib_export
  COMMAND Rscript -e "torchexport::export()"
  COMMENT "Regenerating export code."
  VERBATIM
)
add_dependencies(torchvisionlib torchvisionlib_export)

set_property(TARGET torchvisionlib PROPERTY CXX_STANDARD 17)

target_link_libraries(torchvisionlib "${TORCH_LIBRARIES}")
target_link_libraries(torchvisionlib TorchVision)

# Sync headers and def file with Rcpp interface
add_custom_command(TARGET torchvisionlib POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy "${PROJECT_SOURCE_DIR}/src/torchvisionlib.def" "${PROJECT_SOURCE_DIR}/../inst/def/torchvisionlib.def"
    COMMENT "Copied def file to inst folder."
)

# ------------------------------------------------------------------------------
# CPack Configuration
# ------------------------------------------------------------------------------
set(CPACK_GENERATOR ZIP)
execute_process (
    COMMAND Rscript -e "cat(desc::description\$new(file = '../../DESCRIPTION')\$get('Version'))"
    OUTPUT_VARIABLE CPACK_PACKAGE_VERSION
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

if(DEFINED CUDA_VERSION_STRING)
  set(CPACK_PACKAGE_VERSION "${CPACK_PACKAGE_VERSION}+cu${CUDA_VERSION_MAJOR}${CUDA_VERSION_MINOR}")
else()
  set(CPACK_PACKAGE_VERSION "${CPACK_PACKAGE_VERSION}+cpu")
endif()

if(APPLE)
  set(CPACK_PACKAGE_VERSION "${CPACK_PACKAGE_VERSION}+${CMAKE_SYSTEM_PROCESSOR}")
endif()

include(CPack)

# ------------------------------------------------------------------------------
# Install targets to R package convention: libs/ directory
# ------------------------------------------------------------------------------
set(R_INSTALL_DIR "${PROJECT_SOURCE_DIR}/../inst")

# Install main library to libs/
install(TARGETS torchvisionlib
    LIBRARY DESTINATION "${R_INSTALL_DIR}/libs"
    PUBLIC_HEADER DESTINATION include/torchvisionlib
    RUNTIME DESTINATION "${R_INSTALL_DIR}/libs"
)

# Install torchvision dependency to same folder (avoid nested dirs)
if(UNIX AND NOT APPLE)
    install(FILES "${TORCHVISION_LIB_DIR}/libtorchvision.so"
            DESTINATION "${R_INSTALL_DIR}/libs"
            PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
elseif(APPLE)
    install(FILES "${TORCHVISION_LIB_DIR}/libtorchvision.dylib"
            DESTINATION "${R_INSTALL_DIR}/libs"
            PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
elseif(WIN32)
    install(FILES "${TorchVision_DESTDIR}/bin/torchvision.dll"
            DESTINATION "${R_INSTALL_DIR}/libs")
    install(FILES "${TorchVision_DESTDIR}/lib/torchvision.lib"
            DESTINATION "${R_INSTALL_DIR}/lib")
endif()
