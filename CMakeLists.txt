# lua-protobuf vs 项目版 pbc 对比工程
#
# 构建方式（产物全部落在 build/，源码树不产生任何文件）：
#   cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
#   cmake --build build
#   build/bin/bench.exe
#
# 一键脚本：Windows 用 build.bat（VS 自带 CMake/Ninja，产物 build/bin）；
#           Debian 12 用 build.sh（Unix Makefiles，产物 build/linux/bin）。
# 两者都是 Release，参数 run / test 表示构建后直接跑 bench。

cmake_minimum_required(VERSION 3.17)
project(lua_pb_bench LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 所有产物集中到 build 目录，绝不与源码混在一起
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")

# 四轮优化已全部写死进 pbc 源码，不再有任何优化/A/B 编译开关。
# pbc core 按 C++ 编译(/TP) 与 MServer 引擎一致；lua-protobuf 的 pb.c 按 C 编译。

if(MSVC)
    # /utf-8: 源码是 utf8 无 BOM，中文注释必须按 utf-8 读，否则 MSVC 按 GBK 解析出错
    # 优化级别由 CMAKE_BUILD_TYPE=Release 统一提供 /O2 /Ob2 /DNDEBUG，四个 target 完全相同
    add_compile_options(/W3 /utf-8 /wd4996 /wd4244 /wd4267 /wd4090 /wd4706 /wd4127)
else()
    add_compile_options(-Wall -Wextra)
endif()

# ---------------------------------------------------------------------------
# Lua 5.5.1 源码副本（静态库，与项目实际使用的解释器版本一致）
# ---------------------------------------------------------------------------
file(GLOB LUA_CORE_SRC "${CMAKE_CURRENT_SOURCE_DIR}/lua/*.c")
add_library(lua_core STATIC ${LUA_CORE_SRC})
target_include_directories(lua_core PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/lua")

# ---------------------------------------------------------------------------
# 当前项目使用的 pbc（用户自己的 fork：上游 pbc + pbc_fields 等修改）
# 整个 pbc/ 目录就是唯一的 pbc 源码，pbc_binding 里不再保留副本
# ---------------------------------------------------------------------------
file(GLOB PBC_CORE_SRC "${CMAKE_CURRENT_SOURCE_DIR}/pbc/src/*.c")
add_library(pbc_core STATIC ${PBC_CORE_SRC})
target_include_directories(pbc_core PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/pbc"
    "${CMAKE_CURRENT_SOURCE_DIR}/pbc/src")
# 与项目 engine/deps/CMakeLists.txt 一致：pbc 的 .c 里有 bool 等 C++ 类型，
# 必须强制按 C++ 编译（这也是 pbc 自带 VC 工程的设定）
if(MSVC)
    target_compile_options(pbc_core PRIVATE
        /TP /wd4146 /wd4273 /wd4244 /wd4018 /wd4267)
endif()

# 语法版本编译期确定，默认 proto3；-DPBC_PROTO2=ON 切到 proto2
option(PBC_PROTO2 "pbc 按 proto2 语法注册（repeated 数值字段不默认 packed）" OFF)
if(PBC_PROTO2)
    target_compile_definitions(pbc_core PUBLIC PBC_PROTO2=1)
endif()

# 项目自研的 lua-binding（engine/src/net/codec/pbc_codec，已去掉引擎依赖）
# 只保留兼容层与 binding 源码；pbc core 直接链接上面的 pbc_core
add_library(pbc_binding STATIC
    "${CMAKE_CURRENT_SOURCE_DIR}/pbc_binding/pbc_codec.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/pbc_binding/pbc_module.cpp")
target_include_directories(pbc_binding PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/pbc_binding")
target_link_libraries(pbc_binding PUBLIC pbc_core lua_core)

# ---------------------------------------------------------------------------
# lua-protobuf（starwing/lua-protobuf，pb.c 为单文件实现）
# ---------------------------------------------------------------------------
add_library(lua_pb STATIC "${CMAKE_CURRENT_SOURCE_DIR}/lua-protobuf/pb.c")
target_include_directories(lua_pb PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/lua-protobuf"
    "${CMAKE_CURRENT_SOURCE_DIR}/lua")
target_link_libraries(lua_pb PUBLIC lua_core)

# ---------------------------------------------------------------------------
# 测试运行器：内嵌 Lua 解释器 + 内存统计 + 两个库静态注册
# ---------------------------------------------------------------------------
add_executable(bench "${CMAKE_CURRENT_SOURCE_DIR}/bench/main.cpp")
target_link_libraries(bench PRIVATE lua_core pbc_binding lua_pb)
if(WIN32)
    target_link_libraries(bench PRIVATE psapi)
endif()

# 采样 profiler：/Zi + PDB 才能符号化；默认关闭，profile 时用 -DBENCH_PROFILE=ON
option(BENCH_PROFILE "bench 采样 profiler（生成 PDB，符号化热点函数）" OFF)
if(BENCH_PROFILE AND MSVC)
    target_compile_definitions(bench PRIVATE BENCH_PROFILE)
    target_link_options(bench PRIVATE /DEBUG:FULL)
    if(WIN32)
        target_link_libraries(bench PRIVATE dbghelp)
    endif()
    # 三个被测库也带调试信息，否则静态函数（call_type/wiretype_decode 等）的样本
    # 会误归因到地址上邻近的导出符号
    foreach(_t bench pbc_core lua_core lua_pb)
        if(TARGET ${_t})
            target_compile_options(${_t} PRIVATE /Zi /FS)
        endif()
    endforeach()
endif()

# 运行时脚本复制到 build/bin/lua，proto 复制到 build/bin/proto
set(BENCH_LUA_DIR "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/lua")
set(BENCH_PROTO_DIR "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/proto")
set(BENCH_PB_DIR "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/pb")
file(MAKE_DIRECTORY "${BENCH_LUA_DIR}" "${BENCH_PROTO_DIR}" "${BENCH_PB_DIR}")

file(GLOB BENCH_LUA_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/bench/*.lua"
    "${CMAKE_CURRENT_SOURCE_DIR}/bench/lib/*.lua"
    "${CMAKE_CURRENT_SOURCE_DIR}/lua-protobuf/protoc.lua"
    "${CMAKE_CURRENT_SOURCE_DIR}/lua-protobuf/serpent.lua"
    "${CMAKE_CURRENT_SOURCE_DIR}/lua-protobuf/luaunit.lua")
foreach(f ${BENCH_LUA_FILES})
    get_filename_component(fname "${f}" NAME)
    configure_file("${f}" "${BENCH_LUA_DIR}/${fname}" COPYONLY)
endforeach()

file(GLOB BENCH_PROTO_FILES "${CMAKE_CURRENT_SOURCE_DIR}/bench/proto/*.proto")
foreach(f ${BENCH_PROTO_FILES})
    get_filename_component(fname "${f}" NAME)
    configure_file("${f}" "${BENCH_PROTO_DIR}/${fname}" COPYONLY)
endforeach()

# 项目真实协议样本（server/pb 下 protoc -o 生成的 proto3 descriptor）
file(GLOB BENCH_PB_FILES "${CMAKE_CURRENT_SOURCE_DIR}/bench/pb/*.pb")
foreach(f ${BENCH_PB_FILES})
    get_filename_component(fname "${f}" NAME)
    configure_file("${f}" "${BENCH_PB_DIR}/${fname}" COPYONLY)
endforeach()
