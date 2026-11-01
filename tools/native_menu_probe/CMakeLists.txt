cmake_minimum_required(VERSION 3.14)
project(busybooks_native_menu_probe LANGUAGES CXX)
if(NOT WIN32)
  message(FATAL_ERROR "This probe requires an interactive Windows desktop")
endif()
set(FLUTTER_EPHEMERAL "${CMAKE_CURRENT_SOURCE_DIR}/../../windows/flutter/ephemeral")
set(FLUTTER_WRAPPER "${FLUTTER_EPHEMERAL}/cpp_client_wrapper")
if(NOT EXISTS "${FLUTTER_WRAPPER}/standard_codec.cc")
  message(FATAL_ERROR "Build the Windows application first to obtain its official Flutter wrapper")
endif()
add_executable(busybooks_native_menu_probe
  windows_menu_probe.cpp
  ../../windows/runner/native_menu_host.cpp
  "${FLUTTER_WRAPPER}/core_implementations.cc"
  "${FLUTTER_WRAPPER}/standard_codec.cc")
target_include_directories(busybooks_native_menu_probe PRIVATE
  "${FLUTTER_WRAPPER}/include" "${FLUTTER_EPHEMERAL}")
target_compile_features(busybooks_native_menu_probe PRIVATE cxx_std_17)
target_compile_definitions(busybooks_native_menu_probe PRIVATE NOMINMAX UNICODE _UNICODE)
target_compile_options(busybooks_native_menu_probe PRIVATE /W4 /WX /wd4100 /EHsc)
target_link_libraries(busybooks_native_menu_probe PRIVATE
  "${FLUTTER_EPHEMERAL}/flutter_windows.dll.lib" user32 gdi32)
add_custom_command(TARGET busybooks_native_menu_probe POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${FLUTTER_EPHEMERAL}/flutter_windows.dll"
    "$<TARGET_FILE_DIR:busybooks_native_menu_probe>" VERBATIM)
add_executable(busybooks_menu_selection_test ../../test/src/native_menu_selection_test.cc)
target_compile_features(busybooks_menu_selection_test PRIVATE cxx_std_17)
target_compile_options(busybooks_menu_selection_test PRIVATE /W4 /WX /UNDEBUG)
