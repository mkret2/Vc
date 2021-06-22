set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/cmake")

set(disabled_targets)

include (VcMacros)
include (AddTargetProperty)
include (OptimizeForArchitecture)

set(CXX_FLAGS_BACKUP "${CMAKE_CXX_FLAGS}")

set(_compiler_flags_args WARNING_FLAGS)
if (USE_VC_BUILDTYPE_FLAGS)
    list(APPEND _compiler_flags_args BUILDTYPE_FLAGS)
endif()
vc_set_preferred_compiler_flags(${_compiler_flags_args})

vc_determine_compiler()

if("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "(i686|x86|AMD64|amd64)")
   set(Vc_X86 TRUE)
elseif("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "(arm|aarch32|aarch64)")
   message(WARNING "No optimized implementation of the Vc types available for ${CMAKE_SYSTEM_PROCESSOR}")
   set(Vc_ARM TRUE)
else()
   message(WARNING "No optimized implementation of the Vc types available for ${CMAKE_SYSTEM_PROCESSOR}")
endif()

# TODO: check that 'decltype' compiles
# TODO: check that 'constexpr' compiles
if(NOT Vc_COMPILER_IS_MSVC) # MSVC doesn't provide a switch to turn C++11 on/off AFAIK
   AddCompilerFlag("-std=c++14" CXX_RESULT _ok CXX_FLAGS CMAKE_CXX_FLAGS)
   if(NOT _ok)
      AddCompilerFlag("-std=c++1y" CXX_RESULT _ok CXX_FLAGS CMAKE_CXX_FLAGS)
      if(NOT _ok)
         AddCompilerFlag("-std=c++11" CXX_RESULT _ok CXX_FLAGS CMAKE_CXX_FLAGS)
         if(NOT _ok)
            AddCompilerFlag("-std=c++0x" CXX_RESULT _ok CXX_FLAGS CMAKE_CXX_FLAGS)
            if(NOT _ok)
               message(FATAL_ERROR "Vc 1.x requires C++11, better even C++14. It seems this is not available. If this was incorrectly determined please notify vc-devel@compeng.uni-frankfurt.de")
            endif()
         endif()
      endif()
   endif()
elseif(Vc_MSVC_VERSION LESS 180021114)
   message(FATAL_ERROR "Vc 1.x requires C++11 support. This requires at least Visual Studio 2013 with the Nov 2013 CTP.")
endif()

if(Vc_COMPILER_IS_GCC)
   if(Vc_GCC_VERSION VERSION_GREATER "5.0.0" AND Vc_GCC_VERSION VERSION_LESS "6.0.0")
      UserWarning("GCC 5 goes into an endless loop comiling example_scaling_scalar. Therefore, this target is disabled.")
      list(APPEND disabled_targets
         example_scaling_scalar
         )
   endif()
elseif(Vc_COMPILER_IS_MSVC)
   if(MSVC_VERSION LESS 1700)
      # MSVC before 2012 has a broken std::vector::resize implementation. STL + Vc code will probably not compile.
      # UserWarning in VcMacros.cmake
      list(APPEND disabled_targets
         stlcontainer_sse
         stlcontainer_avx
         )
   endif()
   # Disable warning "C++ exception specification ignored except to indicate a function is not __declspec(nothrow)"
   # MSVC emits the warning for the _UnitTest_Compare desctructor which needs the throw declaration so that it doesn't std::terminate
   AddCompilerFlag("/wd4290")
endif()

if(Vc_COMPILER_IS_INTEL)
   # per default icc is not IEEE compliant, but we need that for verification
   AddCompilerFlag("-fp-model source")
endif()

add_custom_target(other VERBATIM)
add_custom_target(Scalar COMMENT "build Scalar code" VERBATIM)
add_custom_target(SSE COMMENT "build SSE code" VERBATIM)
add_custom_target(AVX COMMENT "build AVX code" VERBATIM)
add_custom_target(AVX2 COMMENT "build AVX2 code" VERBATIM)

AddCompilerFlag(-ftemplate-depth=128 CXX_FLAGS CMAKE_CXX_FLAGS)

set(libvc_compile_flags "-DVc_COMPILE_LIB")
AddCompilerFlag("-fPIC" CXX_FLAGS libvc_compile_flags)

# -fstack-protector is the default of GCC, but at least Ubuntu changes the default to -fstack-protector-strong, which is crazy
AddCompilerFlag("-fstack-protector" CXX_FLAGS libvc_compile_flags)

set(_srcs ${CMAKE_CURRENT_LIST_DIR}/src/const.cpp)
if(Vc_X86)
   list(APPEND _srcs ${CMAKE_CURRENT_LIST_DIR}/src/cpuid.cpp ${CMAKE_CURRENT_LIST_DIR}/src/support_x86.cpp)
   vc_compile_for_all_implementations(_srcs ${CMAKE_CURRENT_LIST_DIR}/src/trigonometric.cpp ONLY SSE2 SSE3 SSSE3 SSE4_1 AVX SSE+XOP+FMA4 AVX+XOP+FMA4 AVX+XOP+FMA AVX+FMA AVX2+FMA+BMI2)
   vc_compile_for_all_implementations(_srcs ${CMAKE_CURRENT_LIST_DIR}/src/sse_sorthelper.cpp ONLY SSE2 SSE4_1 AVX AVX2+FMA+BMI2)
   vc_compile_for_all_implementations(_srcs ${CMAKE_CURRENT_LIST_DIR}/src/avx_sorthelper.cpp ONLY AVX AVX2+FMA+BMI2)
elseif(Vc_ARM)
   list(APPEND _srcs ${CMAKE_CURRENT_LIST_DIR}/src/support_dummy.cpp)
else()
   list(APPEND _srcs ${CMAKE_CURRENT_LIST_DIR}/src/support_dummy.cpp)
endif()

add_library(Vc STATIC ${_srcs})
add_target_property(Vc LABELS "other")

if(XCODE)
   # TODO: document what this does and why it has no counterpart in the non-XCODE logic
   set_target_properties(Vc PROPERTIES XCODE_ATTRIBUTE_GCC_INLINES_ARE_PRIVATE_EXTERN "NO")
   set_target_properties(Vc PROPERTIES XCODE_ATTRIBUTE_GCC_SYMBOLS_PRIVATE_EXTERN "YES")
   set_target_properties(Vc PROPERTIES XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD "c++0x")
   set_target_properties(Vc PROPERTIES XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY "libc++")
elseif(UNIX AND Vc_COMPILER_IS_CLANG)
   # On UNIX (Linux) the standard library used by default typically is libstdc++ (GCC).
   # To get the full clang deal we rather want to build against libc++. This requires
   # additionally the libc++abi and libsupc++ libraries in all linker invokations.
   option(USE_LIBC++ "Use libc++ instead of the system default C++ standard library." OFF)
   if(USE_LIBC++)
      AddCompilerFlag(-stdlib=libc++ CXX_FLAGS CMAKE_CXX_FLAGS CXX_RESULT _use_libcxx)
      if(_use_libcxx)
         find_library(LIBC++ABI c++abi)
         mark_as_advanced(LIBC++ABI)
         if(LIBC++ABI)
            set(CMAKE_REQUIRED_LIBRARIES "${LIBC++ABI};supc++")
            CHECK_CXX_SOURCE_COMPILES("#include <stdexcept>
            #include <iostream>
            void foo() {
              std::cout << 'h' << std::flush << std::endl;
              throw std::exception();
            }
            int main() {
              try { foo(); }
              catch (int) { return 0; }
              return 1;
            }" libcxx_compiles)
            unset(CMAKE_REQUIRED_LIBRARIES)
            if(libcxx_compiles)
               link_libraries(${LIBC++ABI} supc++)
            endif()
         endif()
      endif()
   else()
      CHECK_CXX_SOURCE_COMPILES("#include <tuple>
      std::tuple<int> f() { std::tuple<int> r; return r; }
      int main() { return 0; }
      " tuple_sanity)
      if (NOT tuple_sanity)
         message(FATAL_ERROR "Clang and std::tuple brokenness detected. Please update your compiler.")
      endif()
   endif()
endif()

add_dependencies(other Vc)

target_include_directories(Vc
   PUBLIC
   $<BUILD_INTERFACE:${CMAKE_CURRENT_LIST_DIR}>
   $<INSTALL_INTERFACE:include>
   )
separate_arguments(_defines UNIX_COMMAND "${Vc_DEFINITIONS}")
target_compile_definitions(Vc
   PUBLIC
   ${_defines}
)
separate_arguments(_flags UNIX_COMMAND "${Vc_COMPILE_FLAGS} ${CMAKE_CXX_FLAGS}")
target_compile_options(Vc
   PUBLIC
   ${_flags}
)
target_compile_options(Vc
   PRIVATE
   ${libvc_compile_flags}
)

set(CMAKE_CXX_FLAGS "${CXX_FLAGS_BACKUP}")
