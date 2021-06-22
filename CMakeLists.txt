cmake_minimum_required(VERSION 3.0)

cmake_policy(SET CMP0028 NEW) # Double colon in target name means ALIAS or IMPORTED target.
cmake_policy(SET CMP0048 NEW) # The ``project()`` command manages VERSION variables.
if (POLICY CMP0071)
cmake_policy(SET CMP0071 NEW) # Run auto{moc,uic,gen} on generated files.
endif()

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_BINARY_DIR)
   message(FATAL_ERROR "You don't want to configure in the source directory!")
endif()

if(NOT DEFINED CMAKE_BUILD_TYPE)
   set(CMAKE_BUILD_TYPE Release CACHE STRING
      "Choose the type of build, options are: None Debug Release RelWithDebug RelWithDebInfo MinSizeRel."
      FORCE)
endif()

# read version parts from version.h
file(STRINGS ${CMAKE_CURRENT_SOURCE_DIR}/Vc/version.h _version_lines REGEX "^#define Vc_VERSION_STRING ")
string(REGEX MATCH "([0-9]+)\\.([0-9]+)\\.([0-9]+)" _version_matches "${_version_lines}")

project(Vc VERSION "${CMAKE_MATCH_1}.${CMAKE_MATCH_2}.${CMAKE_MATCH_3}" LANGUAGES C CXX)

option(USE_CCACHE "If enabled, ccache will be used (if it exists on the system) to speed up recompiles." OFF)
if(USE_CCACHE)
   find_program(CCACHE_COMMAND ccache)
   if(CCACHE_COMMAND)
      mark_as_advanced(CCACHE_COMMAND)
      set_property(GLOBAL PROPERTY RULE_LAUNCH_COMPILE "${CCACHE_COMMAND}")
   endif()
endif()

set(USE_VC_BUILDTYPE_FLAGS ON)

include(Vc_submodule.cmake)

if(CMAKE_BUILD_TYPE STREQUAL "" AND NOT CMAKE_CXX_FLAGS MATCHES "-O[123]")
   message(STATUS "WARNING! It seems you are compiling without optimization. Please set CMAKE_BUILD_TYPE.")
endif(CMAKE_BUILD_TYPE STREQUAL "" AND NOT CMAKE_CXX_FLAGS MATCHES "-O[123]")

install(TARGETS Vc EXPORT VcTargets DESTINATION lib${LIB_SUFFIX})
install(DIRECTORY Vc/ DESTINATION include/Vc FILES_MATCHING REGEX "/*.(h|tcc|def)$")
install(FILES
   Vc/Allocator
   Vc/IO
   Vc/Memory
   Vc/SimdArray
   Vc/Utils
   Vc/Vc
   Vc/algorithm
   Vc/array
   Vc/iterators
   Vc/limits
   Vc/simdize
   Vc/span
   Vc/type_traits
   Vc/vector
   DESTINATION include/Vc)

# Generate and install CMake package and modules
include(CMakePackageConfigHelpers)
set(PACKAGE_INSTALL_DESTINATION
   lib${LIB_SUFFIX}/cmake/${PROJECT_NAME}
   )
install(EXPORT ${PROJECT_NAME}Targets
   NAMESPACE ${PROJECT_NAME}::
   DESTINATION ${PACKAGE_INSTALL_DESTINATION}
   EXPORT_LINK_INTERFACE_LIBRARIES
   )
write_basic_package_version_file(
   ${CMAKE_CURRENT_BINARY_DIR}/cmake/${PROJECT_NAME}ConfigVersion.cmake
   VERSION ${PROJECT_VERSION}
   COMPATIBILITY AnyNewerVersion
   )
configure_package_config_file(
   ${CMAKE_SOURCE_DIR}/cmake/${PROJECT_NAME}Config.cmake.in
   ${CMAKE_CURRENT_BINARY_DIR}/cmake/${PROJECT_NAME}Config.cmake
   INSTALL_DESTINATION ${PACKAGE_INSTALL_DESTINATION}
   PATH_VARS CMAKE_INSTALL_PREFIX
   )
install(FILES
   cmake/UserWarning.cmake
   cmake/VcMacros.cmake
   cmake/AddCompilerFlag.cmake
   cmake/CheckCCompilerFlag.cmake
   cmake/CheckCXXCompilerFlag.cmake
   cmake/OptimizeForArchitecture.cmake
   cmake/FindVc.cmake
   ${CMAKE_CURRENT_BINARY_DIR}/cmake/${PROJECT_NAME}Config.cmake
   ${CMAKE_CURRENT_BINARY_DIR}/cmake/${PROJECT_NAME}ConfigVersion.cmake
   DESTINATION ${PACKAGE_INSTALL_DESTINATION}
   )

#Release# option(BUILD_TESTING "Build the testing tree." OFF)
include (CTest)
configure_file(${CMAKE_SOURCE_DIR}/CTestCustom.cmake ${CMAKE_BINARY_DIR}/CTestCustom.cmake COPYONLY)
if(BUILD_TESTING)
   add_custom_target(build_tests ALL VERBATIM)
   add_subdirectory(tests)
endif(BUILD_TESTING)

set(BUILD_EXAMPLES FALSE CACHE BOOL "Build examples.")
if(BUILD_EXAMPLES)
   add_subdirectory(examples)
endif(BUILD_EXAMPLES)

# Hide Vc_IMPL as it is only meant for users of Vc
mark_as_advanced(Vc_IMPL)

find_program(BIN_CAT cat)
mark_as_advanced(BIN_CAT)
if(BIN_CAT)
   file(REMOVE ${CMAKE_BINARY_DIR}/help.txt)
   add_custom_command(OUTPUT ${CMAKE_BINARY_DIR}/help.txt
      COMMAND ${CMAKE_MAKE_PROGRAM} help > ${CMAKE_BINARY_DIR}/help.txt
      VERBATIM
      )
   add_custom_target(cached_help
      ${BIN_CAT} ${CMAKE_BINARY_DIR}/help.txt
      DEPENDS ${CMAKE_BINARY_DIR}/help.txt
      VERBATIM
      )
endif()
