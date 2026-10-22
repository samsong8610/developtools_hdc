cmake_minimum_required(VERSION 3.16)
project(hdcd_lite C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

get_filename_component(HDC_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
get_filename_component(PORT_ROOT "${HDC_ROOT}/.." ABSOLUTE)
if(NOT DEFINED HDCD_DEPS_ROOT)
  set(HDCD_DEPS_ROOT "${PORT_ROOT}/deps")
endif()
if(NOT DEFINED HDCD_PREFIX)
  set(HDCD_PREFIX "${PORT_ROOT}/b/prefix")
endif()

add_compile_definitions(
  HDC_LITE_OSAL HARMONY_PROJECT USE_CONFIG_UV_THREADS SIZE_THREAD_POOL=4
  OPENSSL_SUPPRESS_DEPRECATED JS_JDWP_CONNECT HDC_SUPPORT_ENCRYPT_TCP MEMORY_POOL_ENABLE
)

set(HDC_OSAL_TARGET "linux" CACHE STRING "OSAL backend: linux | liteos_a")
set_property(CACHE HDC_OSAL_TARGET PROPERTY STRINGS linux liteos_a)
if(NOT HDC_OSAL_TARGET MATCHES "^(linux|liteos_a)$")
  message(FATAL_ERROR "HDC_OSAL_TARGET must be linux or liteos_a")
endif()
set(OSAL_DIR osal/${HDC_OSAL_TARGET})
add_library(hdc_osal STATIC
  ${OSAL_DIR}/param.c ${OSAL_DIR}/service.c ${OSAL_DIR}/usb.c
  ${OSAL_DIR}/pty.c ${OSAL_DIR}/proc.c ${OSAL_DIR}/priv.c)
if(HDC_OSAL_TARGET STREQUAL "liteos_a")
  # liteos-like defines (compile/link check; real LiteOS-A toolchain TBD)
  target_compile_definitions(hdc_osal PUBLIC HDC_OSAL_LITEOS_A __LITEOS_A__)
endif()
message(STATUS "hdcd OSAL backend: ${HDC_OSAL_TARGET}")
target_include_directories(hdc_osal PUBLIC
  ${CMAKE_CURRENT_LIST_DIR}/osal/include
  ${CMAKE_CURRENT_LIST_DIR}/osal/include/shim)

set(HASH_OUT_DIR "${CMAKE_BINARY_DIR}/gen")
file(MAKE_DIRECTORY "${HASH_OUT_DIR}")
if(EXISTS "${PORT_ROOT}/gen/hdc_hash_gen.h")
  file(COPY "${PORT_ROOT}/gen/hdc_hash_gen.h" DESTINATION "${HASH_OUT_DIR}")
else()
  file(WRITE "${HASH_OUT_DIR}/hdc_hash_gen.h"
    "#pragma once\n#define HDC_MSG_HASH \"7fdbc1aa8c5fefaa\"\n")
endif()

set(DAEMON_SRC
  ${HDC_ROOT}/src/daemon/daemon.cpp
  ${HDC_ROOT}/src/daemon/daemon_app.cpp
  ${HDC_ROOT}/src/daemon/daemon_forward.cpp
  ${HDC_ROOT}/src/daemon/daemon_ssl.cpp
  ${HDC_ROOT}/src/daemon/daemon_tcp.cpp
  ${HDC_ROOT}/src/daemon/daemon_unity.cpp
  ${HDC_ROOT}/src/daemon/daemon_usb.cpp
  ${HDC_ROOT}/src/daemon/jdwp.cpp
  ${HDC_ROOT}/src/daemon/main.cpp
  ${HDC_ROOT}/src/daemon/shell.cpp
  ${HDC_ROOT}/src/daemon/system_depend.cpp
)
set(COMMON_SRC
  ${HDC_ROOT}/src/common/async_cmd.cpp
  ${HDC_ROOT}/src/common/auth.cpp
  ${HDC_ROOT}/src/common/base.cpp
  ${HDC_ROOT}/src/common/channel.cpp
  ${HDC_ROOT}/src/common/circle_buffer.cpp
  ${HDC_ROOT}/src/common/compress.cpp
  ${HDC_ROOT}/src/common/decompress.cpp
  ${HDC_ROOT}/src/common/entry.cpp
  ${HDC_ROOT}/src/common/file.cpp
  ${HDC_ROOT}/src/common/file_descriptor.cpp
  ${HDC_ROOT}/src/common/forward.cpp
  ${HDC_ROOT}/src/common/header.cpp
  ${HDC_ROOT}/src/common/heartbeat.cpp
  ${HDC_ROOT}/src/common/hdc_ssl.cpp
  ${HDC_ROOT}/src/common/memory_pool.cpp
  ${HDC_ROOT}/src/common/server_cmd_log.cpp
  ${HDC_ROOT}/src/common/session.cpp
  ${HDC_ROOT}/src/common/task.cpp
  ${HDC_ROOT}/src/common/tcp.cpp
  ${HDC_ROOT}/src/common/tlv.cpp
  ${HDC_ROOT}/src/common/transfer.cpp
  ${HDC_ROOT}/src/common/usb.cpp
  ${HDC_ROOT}/src/common/uv_status.cpp
  ${HDC_ROOT}/src/common/connect_validation.cpp
  ${HDC_ROOT}/src/common/hdc_statistic_reporter.cpp
)
if(EXISTS "${HDC_ROOT}/src/common/debug.cpp")
  list(APPEND COMMON_SRC ${HDC_ROOT}/src/common/debug.cpp)
endif()

add_executable(hdcd ${DAEMON_SRC} ${COMMON_SRC})
target_include_directories(hdcd PRIVATE
  ${HDC_ROOT}/src/common ${HDC_ROOT}/src/daemon ${HASH_OUT_DIR}
  ${HDCD_PREFIX}/include
  ${HDCD_DEPS_ROOT}/third_party_libuv/include
  ${HDCD_DEPS_ROOT}/third_party_libuv/src
  ${HDCD_DEPS_ROOT}/third_party_bounds_checking_function/include
  ${HDCD_DEPS_ROOT}/third_party_lz4/lib
  ${CMAKE_CURRENT_LIST_DIR}/osal/include
  ${CMAKE_CURRENT_LIST_DIR}/osal/include/shim
)
target_compile_options(hdcd PRIVATE -fexceptions -O2 -w)
target_link_libraries(hdcd PRIVATE hdc_osal
  ${HDCD_PREFIX}/lib/libuv.a
  ${HDCD_PREFIX}/lib/libssl.a
  ${HDCD_PREFIX}/lib/libcrypto.a
  ${HDCD_PREFIX}/lib/liblz4.a
  ${HDCD_PREFIX}/lib/libsec.a
)
if(NOT DEFINED HDCD_UVX_DIR)
  set(HDCD_UVX_DIR "${PORT_ROOT}/b")
endif()
if(EXISTS "${HDCD_UVX_DIR}/uvx_log_unix.o")
  target_link_libraries(hdcd PRIVATE
    ${HDCD_UVX_DIR}/uvx_log_unix.o ${HDCD_UVX_DIR}/uvx_trace_unix.o)
endif()
set_target_properties(hdcd PROPERTIES LINK_FLAGS "-static")
install(TARGETS hdcd RUNTIME DESTINATION bin)
