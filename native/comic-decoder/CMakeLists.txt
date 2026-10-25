cmake_minimum_required(VERSION 3.18)
project(busybooks_comic_decoder LANGUAGES CXX)
set(archive_source "${CMAKE_CURRENT_LIST_DIR}/../vendor/unrar/unrarsrc-7.2.6.tar.gz")
file(SHA256 "${archive_source}" actual_hash)
if(NOT actual_hash STREQUAL "d1afa67ef4121ebc5986815699e05db0ce8648499e5dca854f282a4c3f72c003")
  message(FATAL_ERROR "The pinned UnRAR source checksum differs")
endif()
set(unrar "${CMAKE_CURRENT_BINARY_DIR}/unrar-source/unrar")
if(NOT EXISTS "${unrar}/dll.hpp")
  file(ARCHIVE_EXTRACT INPUT "${archive_source}" DESTINATION "${CMAKE_CURRENT_BINARY_DIR}/unrar-source")
endif()
# The official makefile's RARDLL objects. No archiver/command-line executable
# or optional system library is installed or discovered at runtime.
set(unrar_objects rar strlist strfn pathfn smallfn global file filefn filcreat
  archive arcread unicode system crypt crc rawread encname resource match timefn
  rdwrfn consio options errhnd rarvm secpassword rijndael getbits sha1 sha256
  blake2s hash extinfo extract volume list find unpack headers threadpool rs16
  cmddata ui largepage filestr scantree dll qopen)
# The Unix makefile omits these Windows implementations. RARDLL still needs
# native version detection and Mark of the Web support on Windows.
if(WIN32)
  list(APPEND unrar_objects isnt motw)
endif()
set(unrar_sources)
foreach(source IN LISTS unrar_objects)
  list(APPEND unrar_sources "${unrar}/${source}.cpp")
endforeach()
add_library(busybooks_unrar STATIC ${unrar_sources})
target_compile_features(busybooks_unrar PRIVATE cxx_std_17)
target_compile_definitions(busybooks_unrar PRIVATE RARDLL UNRAR SILENT _FILE_OFFSET_BITS=64 _LARGEFILE_SOURCE)
if(WIN32)
  target_link_libraries(busybooks_unrar PRIVATE bcrypt winmm)
else()
  target_compile_definitions(busybooks_unrar PRIVATE _UNIX)
endif()
add_executable(busybooks_comic_archive ../comic_archive.cpp)
target_compile_features(busybooks_comic_archive PRIVATE cxx_std_17)
if(NOT WIN32)
  target_compile_definitions(busybooks_comic_archive PRIVATE _UNIX)
endif()
target_include_directories(busybooks_comic_archive PRIVATE "${unrar}")
target_link_libraries(busybooks_comic_archive PRIVATE busybooks_unrar)
install(TARGETS busybooks_comic_archive RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)
install(FILES "${CMAKE_CURRENT_LIST_DIR}/../vendor/unrar/license.txt" "${CMAKE_CURRENT_LIST_DIR}/../vendor/unrar/acknow.txt" DESTINATION "${CMAKE_INSTALL_PREFIX}/share/licenses/unrar" COMPONENT Runtime)
