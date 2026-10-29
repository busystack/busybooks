cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "reader_host.cpp"
  "reading_fonts.cpp"
  "reading_font_channel.cpp"
  "reader_popover.cpp"
  "native_menu_host.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Official WebView2 SDK, pinned independently from the installed Evergreen runtime.
include(FetchContent)
FetchContent_Declare(webview2_sdk URL https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/1.0.3537.50 URL_HASH SHA256=5ea526bbd728adda0da4d31219267e96460494a427e4894c4e09d9f320f4b9aa DOWNLOAD_NAME webview2.zip DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
FetchContent_MakeAvailable(webview2_sdk)
target_include_directories(${BINARY_NAME} PRIVATE "${webview2_sdk_SOURCE_DIR}/build/native/include")
if(CMAKE_SIZEOF_VOID_P EQUAL 8)
  set(WEBVIEW_ARCH x64)
else()
  set(WEBVIEW_ARCH x86)
endif()
target_link_libraries(${BINARY_NAME} PRIVATE "${webview2_sdk_SOURCE_DIR}/build/native/${WEBVIEW_ARCH}/WebView2LoaderStatic.lib" shlwapi shell32 ole32 oleaut32 sapi version dwrite d2d1 windowscodecs)
target_compile_features(${BINARY_NAME} PRIVATE cxx_std_17)

file(GLOB WEBVIEW_LICENSES "${webview2_sdk_SOURCE_DIR}/*LICENSE*" "${webview2_sdk_SOURCE_DIR}/*License*" "${webview2_sdk_SOURCE_DIR}/*Notice*")
if(WEBVIEW_LICENSES)
  install(FILES ${WEBVIEW_LICENSES} DESTINATION "$<TARGET_FILE_DIR:${BINARY_NAME}>/licenses/webview2-sdk" COMPONENT Runtime)
endif()
