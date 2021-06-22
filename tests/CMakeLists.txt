include(AddFileDependencies)

# ICC warns about code that produces reference values. Not useful.
# warning #264: floating-point value does not fit in required floating-point type
AddCompilerFlag("-diag-disable 264" CXX_FLAGS CMAKE_CXX_FLAGS)
# warning #61: integer operation result is out of range
AddCompilerFlag("-diag-disable 61" CXX_FLAGS CMAKE_CXX_FLAGS)

add_definitions(-DCOMPILE_FOR_UNIT_TESTS "-DTESTDATA_DIR=\"${CMAKE_CURRENT_SOURCE_DIR}/testdata/\"") # -DVC_CHECK_ALIGNMENT)
if(Vc_COMPILER_IS_MSVC)
   AddCompilerFlag("/wd4267") # Disable warning "conversion from 'size_t' to 'int', possible loss of data"
   AddCompilerFlag("/wd4723") # Disable warning "potential divide by 0" (suppress doesn't work)
   AddCompilerFlag("/wd4503") # Disable warning "decorated name length exceeded, name was truncated"
endif()

# 32-bit x86 requires SSE for fp math to produce comparable results.
AddCompilerFlag("-mfpmath=sse" CXX_FLAGS Vc_ARCHITECTURE_FLAGS CXX_RESULT _fpmath_ok)

set(Vc_SCALAR_FLAGS "${Vc_ARCHITECTURE_FLAGS};-DVc_IMPL=Scalar")
set(Vc_SSE_FLAGS    "${Vc_ARCHITECTURE_FLAGS};-DVc_IMPL=SSE")
set(Vc_AVX_FLAGS    "${Vc_ARCHITECTURE_FLAGS};-DVc_IMPL=AVX")
set(Vc_AVX2_FLAGS   "${Vc_ARCHITECTURE_FLAGS};-DVc_IMPL=AVX2")

if(USE_XOP)
   set(Vc_SSE_FLAGS  "${Vc_SSE_FLAGS}+XOP")
   set(Vc_AVX_FLAGS  "${Vc_AVX_FLAGS}+XOP")
endif()
if(USE_FMA)
   set(Vc_SSE_FLAGS  "${Vc_SSE_FLAGS}+FMA")
   set(Vc_AVX_FLAGS  "${Vc_AVX_FLAGS}+FMA")
   set(Vc_AVX2_FLAGS "${Vc_AVX2_FLAGS}+FMA")
elseif(USE_FMA4)
   set(Vc_SSE_FLAGS  "${Vc_SSE_FLAGS}+FMA4")
   set(Vc_AVX_FLAGS  "${Vc_AVX_FLAGS}+FMA4")
endif()
if(USE_BMI2)
   set(Vc_AVX2_FLAGS "${Vc_AVX2_FLAGS}+BMI2")
endif()

if(DEFINED Vc_INSIDE_ROOT)
   set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "")  # Reset the ROOT default executable destination
   set(Vc_TEST_TARGET_PREFIX "vc-")
else()
   set(Vc_TEST_TARGET_PREFIX "")
endif()

# don't warn about sanity checks:
if(Vc_COMPILER_IS_CLANG)
   # GCC does not complain about the following flags until much later. Therefore
   # the AddCompilerFlag logic doesn't work as intended.
   AddCompilerFlag(-Wno-tautological-constant-out-of-range-compare)
   AddCompilerFlag(-Wno-tautological-compare)
endif()

CHECK_CXX_SOURCE_COMPILES("#include <cxxabi.h>
int main() { return 0; }" cxx_abi_header_works)
if(cxx_abi_header_works)
   add_definitions(-DHAVE_CXX_ABI_H)
endif()

macro(vc_set_first_flag_of _result)
   set(${_result})
   foreach(_flag ${ARGN})
      AddCompilerFlag("${_flag}" CXX_FLAGS ${_result} CXX_RESULT _ok)
      if(_ok)
         break()
      endif()
   endforeach()
endmacro()

vc_set_first_flag_of(_sse2_flag "-xSSE2" "-msse2" "/arch:SSE2")
vc_set_first_flag_of(_sse4_1_flag "-xSSE4.1" "-msse4.1" "/arch:SSE2")
vc_set_first_flag_of(_avx_flag "-xAVX" "-mavx" "/arch:AVX")
vc_set_first_flag_of(_avx2_flag "-xCORE-AVX2" "-mavx2" "/arch:AVX2")
macro(vc_add_run_target _target)
   if("${CMAKE_GENERATOR}" MATCHES "Visual Studio")
      # do nothing. This just clutters the solution explorer
   else()
      add_custom_target(run_${_target}
         ${_target} -v
         DEPENDS ${_target}
         COMMENT "Execute ${_target} test"
         VERBATIM
         )
      list(APPEND _run_targets "run_${_target}")
   endif()
endmacro()

macro(vc_set_test_target_properties _target _impl _compile_flags)
   target_link_libraries(${_target} Vc)
   set_target_properties(${_target} PROPERTIES XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD "c++0x")
   set_target_properties(${_target} PROPERTIES XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY "libc++")
   add_target_property(${_target} COMPILE_FLAGS "${_extra_flags}")
   set_property(TARGET ${_target} APPEND PROPERTY COMPILE_OPTIONS ${_compile_flags})
   add_target_property(${_target} LABELS "${_impl}")
   add_dependencies(build_tests ${_target})
   add_dependencies(${_impl} ${_target})
   add_test(${Vc_TEST_TARGET_PREFIX}${_target} "${CMAKE_CURRENT_BINARY_DIR}/${_target}")
   set_property(TEST ${Vc_TEST_TARGET_PREFIX}${_target} PROPERTY LABELS "${_impl}")
   vc_add_run_target(${_target})
endmacro()

macro(vc_add_test _name)
   set(_extra_flags)
   set(name ${_name})
   set(_state 0)
   if(Vc_X86)
      set(_targets "Scalar;SSE;AVX1;AVX2")
   else()
      set(_targets "Scalar")
   endif()
   foreach(_arg ${ARGN})
      if("${_arg}" STREQUAL "FLAGS")
         set(_state 0)
      elseif("${_arg}" STREQUAL "TARGETS")
         set(_targets)
         set(_state 1)
      elseif(_state EQUAL 0)
         set(_extra_flags "${_extra_flags} -D${_arg}")
         set(name "${name}_${_arg}")
      elseif(_state EQUAL 1)
         if("${_arg}" STREQUAL "AVX")
            list(APPEND _targets "AVX1")
         else()
            list(APPEND _targets "${_arg}")
         endif()
      endif()
   endforeach()
   string(REPLACE "=" "_" name "${name}")

   set(_run_targets)

   set(_target "${name}_scalar")
   list(FIND disabled_targets ${_target} _disabled)
   if(_disabled EQUAL -1 AND "${_targets}" MATCHES "Scalar")
      file(GLOB _extra_deps "${CMAKE_SOURCE_DIR}/Vc/scalar/*.tcc" "${CMAKE_SOURCE_DIR}/Vc/scalar/*.h" "${CMAKE_SOURCE_DIR}/Vc/common/*.h")
      add_file_dependencies(${_name}.cpp "${_extra_deps}")
      add_executable(${_target} EXCLUDE_FROM_ALL ${_name}.cpp)
      vc_set_test_target_properties(${_target} Scalar "${Vc_SCALAR_FLAGS}")
   endif()

   if(USE_SSE2 AND NOT Vc_SSE_INTRINSICS_BROKEN AND "${_targets}" MATCHES "SSE")
      set(_target "${name}_sse")
      list(FIND disabled_targets ${_target} _disabled)
      if(_disabled EQUAL -1)
         file(GLOB _extra_deps "${CMAKE_SOURCE_DIR}/Vc/sse/*.tcc" "${CMAKE_SOURCE_DIR}/Vc/sse/*.h" "${CMAKE_SOURCE_DIR}/Vc/common/*.h")
         add_file_dependencies(${_name}.cpp "${_extra_deps}")
         add_executable(${_target} EXCLUDE_FROM_ALL ${_name}.cpp)
         vc_set_test_target_properties(${_target} SSE "${Vc_SSE_FLAGS}")
      endif()
   endif()

   if(USE_AVX AND "${_targets}" MATCHES "AVX1")
      set(_target "${name}_avx")
      list(FIND disabled_targets ${_target} _disabled)
      if(_disabled EQUAL -1)
         file(GLOB _extra_deps "${CMAKE_SOURCE_DIR}/Vc/avx/*.tcc" "${CMAKE_SOURCE_DIR}/Vc/avx/*.h" "${CMAKE_SOURCE_DIR}/Vc/common/*.h")
         add_file_dependencies(${_name}.cpp "${_extra_deps}")
         add_executable(${_target} EXCLUDE_FROM_ALL ${_name}.cpp)
         vc_set_test_target_properties(${_target} AVX "${Vc_AVX_FLAGS}")
      endif()
   endif()

   if(USE_AVX2 AND "${_targets}" MATCHES "AVX2")
      set(_target "${name}_avx2")
      list(FIND disabled_targets ${_target} _disabled)
      if(_disabled EQUAL -1)
         file(GLOB _extra_deps "${CMAKE_SOURCE_DIR}/Vc/avx/*.tcc" "${CMAKE_SOURCE_DIR}/Vc/avx/*.h" "${CMAKE_SOURCE_DIR}/Vc/common/*.h")
         add_file_dependencies(${_name}.cpp "${_extra_deps}")
         add_executable(${_target} EXCLUDE_FROM_ALL ${_name}.cpp)
         vc_set_test_target_properties(${_target} AVX2 "${Vc_AVX2_FLAGS}")
      endif()
   endif()

   if(_run_targets)
      add_custom_target(run_${name}_all
         COMMENT "Execute all ${name} tests"
         VERBATIM
         )
      add_dependencies(run_${name}_all ${_run_targets})
   endif()

endmacro(vc_add_test)

vc_add_test(types)
vc_add_test(subscript)
vc_add_test(type_traits)
vc_add_test(stlcontainer)
vc_add_test(scalaraccess)
vc_add_test(memory)
vc_add_test(arithmetics)
vc_add_test(simdize)
vc_add_test(implicit_type_conversion)
vc_add_test(iterators)
vc_add_test(load)
vc_add_test(store)
vc_add_test(gather)
vc_add_test(scatter)
vc_add_test(ulp)
vc_add_test(logarithm)
vc_add_test(trigonometric)
vc_add_test(math)
vc_add_test(gh200)
vc_add_test(reductions)
vc_add_test(mask)
vc_add_test(utils)
vc_add_test(sorted)
vc_add_test(random)
vc_add_test(deinterleave)
vc_add_test(gatherinterleavedmemory)
vc_add_test(scatterinterleavedmemory)
vc_add_test(casts Vc_DEFAULT_TYPES)
if(Vc_X86)
   vc_add_test(gather Vc_USE_BSF_GATHERS TARGETS SSE AVX AVX2)
   vc_add_test(gather Vc_USE_POPCNT_BSF_GATHERS TARGETS SSE AVX AVX2)
   vc_add_test(gather Vc_USE_SET_GATHERS TARGETS SSE AVX AVX2)
   vc_add_test(scatter Vc_USE_BSF_SCATTERS TARGETS SSE AVX AVX2)
   vc_add_test(scatter Vc_USE_POPCNT_BSF_SCATTERS TARGETS SSE AVX AVX2)
   vc_add_test(logarithm Vc_LOG_ILP TARGETS SSE AVX AVX2)
   vc_add_test(logarithm Vc_LOG_ILP2 TARGETS SSE AVX AVX2)
   vc_add_test(scatterinterleavedmemory Vc_USE_MASKMOV_SCATTER TARGETS SSE AVX AVX2)
endif()
option(BUILD_EXTRA_CAST_TESTS "build all possible combinations of simd_cast tests (compiles for a very long time)" FALSE)
if(BUILD_EXTRA_CAST_TESTS)
   vc_add_test(casts Vc_EXTRA_TYPES)
   foreach(n 1 2 3 4 5 8 16 17 31)
      vc_add_test(casts Vc_FROM_N=${n})
      vc_add_test(casts Vc_TO_N=${n})
      foreach(m 1 2 3 4 5 8 16 17 31)
         vc_add_test(casts Vc_FROM_N=${m} Vc_TO_N=${n})
      endforeach()
   endforeach()
endif()
vc_add_test(simdarray)

set(incdirs)
get_target_property(_incdirs Vc INCLUDE_DIRECTORIES)
foreach(_d ${_incdirs})
   list(APPEND incdirs "-I${_d}")
endforeach()

separate_arguments(_flags UNIX_COMMAND "${CMAKE_CXX_FLAGS} ${Vc_DEFINITIONS}")
list(APPEND _flags ${Vc_COMPILE_FLAGS})
set(_tmp)
foreach(_f ${_flags})
   if(_f MATCHES "^-m" OR _f MATCHES "^/arch:" OR _f MATCHES "^-x")
      # nothing
   elseif(_f MATCHES "^/[A-Za-z]")
      string(SUBSTRING "${_f}" 1 -1 _f)
      list(APPEND _tmp "-${_f}")
   else()
      list(APPEND _tmp "${_f}")
   endif()
endforeach()
set(_flags "${_tmp}")

# Test ABI on 64-bit x86: Vector/Mask arguments and return values should pass via registers.
# The 32 bit ABI only allows passing via the stack, so nothing useful to test there.
if(${CMAKE_SYSTEM_PROCESSOR} MATCHES "(x86_64|AMD64|amd64)")
   macro(test_abi _target _impl)
      set(_test test_${_target})
      set(asmfile "${_target}.i")
      add_custom_command(OUTPUT ${asmfile}
         COMMAND ${CMAKE_CXX_COMPILER}
         ${incdirs} ${_flags} -O1 -DVc_IMPL=${_impl} ${ARGN} -S -o ${asmfile}
         ${CMAKE_CURRENT_SOURCE_DIR}/abi.cpp
         DEPENDS abi.cpp ${CMAKE_SOURCE_DIR}/Vc/*/*.h ${CMAKE_SOURCE_DIR}/Vc/*/*.tcc
         WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
         COMMENT "Build ABI test: ${asmfile}"
         VERBATIM
         )
      add_custom_target(${_target} DEPENDS ${asmfile})
      add_target_property(${_target} LABELS "${_impl}")
      add_dependencies(${_impl} ${_target})
      add_dependencies(build_tests ${_target})

      add_test(NAME ${_test}
         WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
         COMMAND ${CMAKE_COMMAND} -DASM=${asmfile} -DIMPL=${_impl}
         -DCOMPILER_IS_CLANG=${Vc_COMPILER_IS_CLANG} -DSYSTEM_NAME=${CMAKE_SYSTEM_NAME}
         -P ${CMAKE_CURRENT_SOURCE_DIR}/abi.cmake
         )
      set_property(TEST ${_test} PROPERTY LABELS "${_impl}")
      add_custom_target(run_${_target}
         ${CMAKE_COMMAND} -DASM=${asmfile} -DIMPL=${_impl}
         -DCOMPILER_IS_CLANG=${Vc_COMPILER_IS_CLANG} -DSYSTEM_NAME=${CMAKE_SYSTEM_NAME}
         -P ${CMAKE_CURRENT_SOURCE_DIR}/abi.cmake
         WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
         DEPENDS ${asmfile}
         COMMENT "Execute ${_target} test"
         VERBATIM
         )
   endmacro()

   if("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "[x3-7]86")
      test_abi(abi_SSE     SSE  ${_sse2_flag})
      test_abi(abi_SSE_AVX SSE  ${_avx_flag})
      if(NOT Vc_AVX_INTRINSICS_BROKEN)
         test_abi(abi_AVX     AVX  ${_avx_flag})
         test_abi(abi_AVX2    AVX2 ${_avx2_flag})
      endif()
   endif()
endif()

if(Vc_X86 AND USE_SSE2 AND NOT Vc_SSE_INTRINSICS_BROKEN)
   list(FIND disabled_targets sse_blend _disabled)
   if(_disabled EQUAL -1)
      add_executable(sse2_blend EXCLUDE_FROM_ALL sse_blend.cpp)
      add_target_property(sse2_blend COMPILE_DEFINITIONS "Vc_IMPL=SSE2")
      set_property(TARGET sse2_blend APPEND PROPERTY COMPILE_OPTIONS "${_sse2_flag}")
      add_target_property(sse2_blend LABELS "SSE")
      add_dependencies(build_tests sse2_blend)
      add_dependencies(SSE sse2_blend)
      add_test(${Vc_TEST_TARGET_PREFIX}sse2_blend "${CMAKE_CURRENT_BINARY_DIR}/sse2_blend")
      set_property(TEST ${Vc_TEST_TARGET_PREFIX}sse2_blend PROPERTY LABELS "SSE")
      target_link_libraries(sse2_blend Vc)

      if(USE_SSE4_1)
         add_executable(sse4_blend EXCLUDE_FROM_ALL sse_blend.cpp)
         add_target_property(sse4_blend COMPILE_DEFINITIONS "Vc_IMPL=SSE4_1")
         set_property(TARGET sse4_blend APPEND PROPERTY COMPILE_OPTIONS ${Vc_ARCHITECTURE_FLAGS})
         add_target_property(sse4_blend LABELS "SSE")
         add_dependencies(build_tests sse4_blend)
         add_dependencies(SSE sse4_blend)
         add_test(${Vc_TEST_TARGET_PREFIX}sse4_blend "${CMAKE_CURRENT_BINARY_DIR}/sse4_blend")
         set_property(TEST ${Vc_TEST_TARGET_PREFIX}sse4_blend PROPERTY LABELS "SSE")
         target_link_libraries(sse4_blend Vc)
      endif()
   endif()
endif()

macro(vc_add_general_test _name)
   add_executable(${_name} EXCLUDE_FROM_ALL ${_name}.cpp )
   target_link_libraries(${_name} Vc)
   add_target_property(${_name} LABELS "other")
   set_property(TARGET ${_name} APPEND PROPERTY COMPILE_OPTIONS "${Vc_ARCHITECTURE_FLAGS}")
   add_dependencies(build_tests ${_name})
   add_dependencies(other ${_name})
   add_test(${Vc_TEST_TARGET_PREFIX}${_name} "${CMAKE_CURRENT_BINARY_DIR}/${_name}")
   set_property(TEST ${Vc_TEST_TARGET_PREFIX}${_name} PROPERTY LABELS "other")
   vc_add_run_target(${_name})
endmacro()

if(_last_target_arch STREQUAL "auto" AND NOT Vc_AVX_INTRINSICS_BROKEN AND Vc_X86)
   vc_add_general_test(supportfunctions)
endif()
vc_add_general_test(alignmentinheritance)
vc_add_general_test(alignedbase)

# compile and link test for targets that need to link lots of stuff together
add_library(linkTestLibDynamic1 SHARED EXCLUDE_FROM_ALL linkTestLib0.cpp linkTestLib1.cpp)
add_library(linkTestLibDynamic2 SHARED EXCLUDE_FROM_ALL linkTestLib0.cpp linkTestLib1.cpp)
add_library(linkTestLibStatic STATIC EXCLUDE_FROM_ALL linkTestLib2.cpp linkTestLib3.cpp)
add_executable(linkTest EXCLUDE_FROM_ALL linkTest0.cpp linkTest1.cpp)
add_dependencies(build_tests linkTest)
add_dependencies(other linkTest)
target_link_libraries(linkTestLibDynamic1 Vc)
target_link_libraries(linkTestLibDynamic2 Vc)
add_target_property(linkTestLibDynamic1 COMPILE_FLAGS "-DPOSTFIX=A")
add_target_property(linkTestLibDynamic2 COMPILE_FLAGS "-DPOSTFIX=B")
set_property(TARGET linkTestLibDynamic1 APPEND PROPERTY COMPILE_OPTIONS "${Vc_ARCHITECTURE_FLAGS}")
set_property(TARGET linkTestLibDynamic2 APPEND PROPERTY COMPILE_OPTIONS "${Vc_ARCHITECTURE_FLAGS}")
set_property(TARGET linkTestLibStatic APPEND PROPERTY COMPILE_OPTIONS "${Vc_ARCHITECTURE_FLAGS}")
set_property(TARGET linkTest APPEND PROPERTY COMPILE_OPTIONS "${Vc_ARCHITECTURE_FLAGS}")
target_link_libraries(linkTestLibStatic Vc)
target_link_libraries(linkTest Vc linkTestLibDynamic1 linkTestLibDynamic2 linkTestLibStatic)
