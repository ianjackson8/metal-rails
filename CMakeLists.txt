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
# commit pinned in X86RECOMP, on Awis13/x86recomp's `liberty` branch).
set(X86RECOMP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/vendor/x86recomp"
    CACHE PATH "x86recomp source tree")
if(NOT EXISTS "${X86RECOMP_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "no x86recomp in ${X86RECOMP_DIR}: clone the commit in X86RECOMP there")
endif()
add_subdirectory("${X86RECOMP_DIR}" x86recomp)

# Milestones 1-2 (feasibility): only the lifter is built
# (cmake --build --preset release --target recomp_lift); tools/lift.sh
# then writes generated/ from the player's own install. The game target
# (recomp_add_lifted + runtime) comes with milestone 3.
