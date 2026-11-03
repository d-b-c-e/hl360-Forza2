# forza2 - ReXGlue Recompiled Project
#
# SDK boilerplate lives in generated/rexglue.cmake.

cmake_minimum_required(VERSION 3.25)
project(forza2 LANGUAGES CXX)
enable_language(C)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

option(FORZA2_USE_COMMITTED_GENERATED "Use the verified committed guest sources without running codegen" OFF)
include(generated/rexglue.cmake)

# The build runs `rexglue codegen` on assets/default.xex first. The game is not
# part of the repository, so without it codegen is swapped for a no-op and the
# committed generated/ sources are compiled as they are. Drop your default.xex
# into assets/ (the launcher's import puts it in game/) to regenerate.
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/assets/default.xex")
    if(WIN32)
        set(_forza2_codegen_stub "${CMAKE_CURRENT_SOURCE_DIR}/cmake/codegen_skipped.cmd")
    else()
        set(_forza2_codegen_stub "${CMAKE_CURRENT_SOURCE_DIR}/cmake/codegen_skipped.sh")
    endif()
    foreach(_config "" _DEBUG _RELEASE _RELWITHDEBINFO)
        set_target_properties(rex::rexglue PROPERTIES IMPORTED_LOCATION${_config} "${_forza2_codegen_stub}")
    endforeach()
    message(STATUS "forza2: no assets/default.xex - building the committed generated/ code")
endif()

# Sources
set(FORZA2_SOURCES
    src/main.cpp
    src/profile.cpp
    src/crash_report.cpp
    src/stream_guard.cpp
    src/diag_hooks.cpp
    src/log_filter.cpp
    src/frame_stats.cpp
    src/shader_warmup.cpp
    src/scripted_input.cpp
    src/dlc.cpp
)

if(WIN32)
    add_executable(forza2 WIN32 ${FORZA2_SOURCES})
    target_sources(forza2 PRIVATE src/provider_free.cpp src/provider_free_io.c src/provider_free_network.cpp)
else()
    add_executable(forza2 ${FORZA2_SOURCES} src/provider_free_disabled.cpp)
endif()

rexglue_setup_target(forza2 GPU_PLUGINS xenos)
if(WIN32 AND CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "GNU" AND
   (CMAKE_SYSTEM_PROCESSOR MATCHES "^(AMD64|amd64|x86_64)$" OR MSVC_CXX_ARCHITECTURE_ID STREQUAL "x64"))
    # Match the installed build's SSE4.1 baseline. Otherwise SIMDE's vrfin
    # fallback emits roundevenf, which is not supplied by the Windows UCRT.
    target_compile_options(forza2 PRIVATE -msse4.1)
    target_compile_options(forza2_recomp PRIVATE -msse4.1)
endif()
# __imp_ is the COFF import-address prefix. Use unambiguous local names for
# overridden exports in both guest mappings/calls and host definitions; never
# rely on duplicate-symbol link ordering or /force:multiple.
if(WIN32)
set(FORZA2_LOCAL_EXPORTS XamInputGetState XamInputGetCapabilities XamInputSetState
    XamInputGetKeystroke XamUserGetName XamUserGetGamerTag XamUserGetSigninInfo)
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/src/provider_free_network.def" _fm2_net_rows REGEX "^FM2_NET")
foreach(_row IN LISTS _fm2_net_rows)
    string(REGEX REPLACE "FM2_NET\\(([A-Za-z0-9_]+),.*" "\\1" _name "${_row}")
    list(APPEND FORZA2_LOCAL_EXPORTS "${_name}")
endforeach()
foreach(_name IN LISTS FORZA2_LOCAL_EXPORTS)
    target_compile_definitions(forza2 PRIVATE "__imp__${_name}=Fm2Native_${_name}")
    target_compile_definitions(forza2_recomp PRIVATE "__imp__${_name}=Fm2Native_${_name}")
endforeach()
endif()
if(WIN32)
    target_link_libraries(forza2 PRIVATE dbghelp)
endif()

# Launcher: profiles, settings, ISO import (launcher/).
option(FORZA2_BUILD_LAUNCHER "Build the independent importer/settings launcher" ON)
if(FORZA2_BUILD_LAUNCHER)
    add_subdirectory(launcher)
endif()

# Port settings ship next to the exe (the runtime reads <exe dir>/forza2.toml).
add_custom_command(TARGET forza2 POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        ${CMAKE_CURRENT_SOURCE_DIR}/config/forza2.toml $<TARGET_FILE_DIR:forza2>/forza2.toml)
