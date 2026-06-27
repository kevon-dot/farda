# Farda Smart Pill Bottle - ESP-IDF v5.4.1 project (REFERENCE REIMPLEMENTATION)
#
# UNVERIFIED REFERENCE BUILD. This is NOT binary-equivalent to the shipped
# Smart_Pill_Bottle.bin. It reconstructs the documented interface/behaviour and
# bakes in the B1-B5 security fixes from the audit. Requires hardware bring-up
# and bench validation before flashing any real device.
cmake_minimum_required(VERSION 3.16)

# Derive git describe / commit info for embedding in the app descriptor and
# telemetry (B5). ESP-IDF already embeds `git describe` into the app
# descriptor; we additionally expose SPB_GIT_REV as a compile definition.
execute_process(
    COMMAND git describe --always --dirty --tags
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    OUTPUT_VARIABLE SPB_GIT_REV
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)
if(NOT SPB_GIT_REV)
    set(SPB_GIT_REV "unknown")
endif()
add_compile_definitions(SPB_GIT_REV="${SPB_GIT_REV}")

# B5: release builds must refuse a dirty working tree. The reconstruction
# default is a debug build; CI / maintainers set SPB_RELEASE=1 for production.
if(DEFINED ENV{SPB_RELEASE} AND "$ENV{SPB_RELEASE}" STREQUAL "1")
    if(SPB_GIT_REV MATCHES "dirty")
        message(FATAL_ERROR
            "SPB_RELEASE build refuses a dirty working tree (git rev: ${SPB_GIT_REV}). "
            "Commit/clean the tree before producing a release image.")
    endif()
endif()

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(Smart_Pill_Bottle)
