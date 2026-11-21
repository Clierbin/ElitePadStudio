cmake_minimum_required(VERSION 3.20)
project(xbox_pi5_android LANGUAGES C CXX)
if(NOT ANDROID OR NOT ANDROID_ABI STREQUAL "arm64-v8a")
  message(FATAL_ERROR "Use Android NDK with ANDROID_ABI=arm64-v8a")
endif()
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(LIBUSB "${CMAKE_CURRENT_SOURCE_DIR}/vendor/libusb")
add_library(usb-1.0 SHARED
  ${LIBUSB}/libusb/core.c ${LIBUSB}/libusb/descriptor.c
  ${LIBUSB}/libusb/hotplug.c ${LIBUSB}/libusb/io.c
  ${LIBUSB}/libusb/sync.c ${LIBUSB}/libusb/strerror.c
  ${LIBUSB}/libusb/os/linux_usbfs.c ${LIBUSB}/libusb/os/events_posix.c
  ${LIBUSB}/libusb/os/threads_posix.c ${LIBUSB}/libusb/os/linux_netlink.c)
target_include_directories(usb-1.0 PRIVATE
  ${LIBUSB}/android ${LIBUSB}/libusb ${LIBUSB}/libusb/os)
target_compile_options(usb-1.0 PRIVATE -fvisibility=hidden)
target_compile_definitions(usb-1.0 PRIVATE _GNU_SOURCE)
target_link_libraries(usb-1.0 PRIVATE log)
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/include/libusb-1.0")
configure_file(${LIBUSB}/libusb/libusb.h "${CMAKE_CURRENT_BINARY_DIR}/include/libusb-1.0/libusb.h" COPYONLY)
file(GLOB XOW_SOURCES CONFIGURE_DEPENDS
  vendor/xow/*.cpp vendor/xow/controller/*.cpp
  vendor/xow/dongle/*.cpp vendor/xow/utils/*.cpp)
add_executable(xow ${XOW_SOURCES})
target_include_directories(xow PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/include")
target_compile_definitions(xow PRIVATE
  VERSION="d335d60-android-pi5-r4-profiles1" FIRMWARE="/data/local/tmp/xbox-pi5/xow_dongle.bin")
target_compile_options(xow PRIVATE -Wall -Wextra)
target_link_libraries(xow PRIVATE usb-1.0)
add_executable(usb-probe src/usb-probe.c)
target_include_directories(usb-probe PRIVATE ${LIBUSB}/libusb)
target_link_libraries(usb-probe PRIVATE usb-1.0)
add_executable(input-dump src/input-dump.c)
foreach(t usb-1.0 xow usb-probe input-dump)
  target_link_options(${t} PRIVATE -Wl,-z,max-page-size=16384)
endforeach()
