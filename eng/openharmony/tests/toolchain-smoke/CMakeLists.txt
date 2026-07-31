cmake_minimum_required(VERSION 3.16)
project(OpenHarmonyToolchainSmoke C)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "OHOS")
    message(FATAL_ERROR "Expected CMAKE_SYSTEM_NAME=OHOS, found ${CMAKE_SYSTEM_NAME}")
endif()

if(NOT CLR_CMAKE_TARGET_OS STREQUAL "openharmony")
    message(FATAL_ERROR "Expected CLR_CMAKE_TARGET_OS=openharmony, found ${CLR_CMAKE_TARGET_OS}")
endif()

if(NOT OHOS_ARCH STREQUAL "arm64-v8a" AND NOT OHOS_ARCH STREQUAL "x86_64")
    message(FATAL_ERROR "Unexpected OHOS_ARCH: ${OHOS_ARCH}")
endif()

add_library(openharmony_toolchain_smoke STATIC smoke.c)
