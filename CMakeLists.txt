cmake_minimum_required(VERSION 3.25)
project(metal_rails LANGUAGES C CXX)
if(APPLE)
  enable_language(OBJCXX)  # x86recomp's Metal device (gfx/metal_device.mm)
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
# x86recomp's runtime and HLE modules are shared libraries: rebuilding one
# does not relink the game.
set(CMAKE_LINK_DEPENDS_NO_SHARED ON)

# x86recomp: the lifter, x87 model and runtime (vendor/x86recomp, the
# commit pinned in X86RECOMP: ianjackson8/x86recomp, a fork of
# Awis13/x86recomp's `liberty` branch).
set(X86RECOMP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/vendor/x86recomp"
    CACHE PATH "x86recomp source tree")
# The Steamworks SDK for the steam_api bridge (x86recomp's recomp_steam):
# RECOMP_STEAMWORKS_SDK, else STEAMWORKS_SDK from tools/local.env (untracked:
# a local path). Version 1.53a: its interface versions are the game's.
if(NOT RECOMP_STEAMWORKS_SDK AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tools/local.env")
  file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/tools/local.env" _sdk REGEX "^STEAMWORKS_SDK=")
  if(_sdk)
    string(REGEX REPLACE "^STEAMWORKS_SDK=\"?([^\"]*)\"?$" "\\1" _sdk "${_sdk}")
    set(RECOMP_STEAMWORKS_SDK "${_sdk}" CACHE PATH "Steamworks SDK sdk/ directory")
  endif()
endif()
if(NOT EXISTS "${X86RECOMP_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "no x86recomp in ${X86RECOMP_DIR}: clone the commit in X86RECOMP there")
endif()
add_subdirectory("${X86RECOMP_DIR}" x86recomp)

# The game: runtime + HLE + lifted code (generated/, written by
# tools/lift.sh from the player's own install: RailWorks.exe and
# plugins/GameManagerVC.dll in one multi-module lift). Absent until the
# first lift, so a fresh checkout still builds the lifter.
recomp_add_lifted(railworks_lifted "${CMAKE_CURRENT_SOURCE_DIR}/generated")
if(TARGET railworks_lifted)
  add_executable(railworks src/main.cpp $<TARGET_OBJECTS:railworks_lifted>)
  target_link_libraries(railworks PRIVATE recomp_runtime recomp_d3d9
                        recomp_xinput recomp_dinput8)
  # recomp_ucrt (UCRT, VCRUNTIME140, MSVCP140) was written for x64 guests.
  # Linked only with an x86recomp that marks those handlers HLE64_ONLY, so
  # a 32-bit call into one not yet audited for 32-bit guests is a fatal
  # error naming it rather than a silent 8-byte pointer access.
  # steam_api.dll to the native Steam client: built by x86recomp when
  # RECOMP_STEAMWORKS_SDK names an SDK with the game's interface versions
  # (1.53a; tools/local.env STEAMWORKS_SDK).
  if(TARGET recomp_steam)
    target_link_libraries(railworks PRIVATE recomp_steam)
  else()
    message(STATUS "railworks: no recomp_steam (set RECOMP_STEAMWORKS_SDK); Steam calls will be fatal")
  endif()
  file(READ "${X86RECOMP_DIR}/src/runtime/hle/hle.h" _hle_h)
  if(_hle_h MATCHES "HLE64_ONLY")
    target_link_libraries(railworks PRIVATE recomp_ucrt)
  else()
    message(STATUS "railworks: x86recomp has no HLE64_ONLY; recomp_ucrt not linked")
  endif()
  set_target_properties(railworks PROPERTIES ENABLE_EXPORTS ON)  # names in fault backtraces
endif()
