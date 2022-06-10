cmake_minimum_required(VERSION 3.5)

project(pbc-test LANGUAGES C CXX)

set(CMAKE_C_STANDARD 99)
set(CMAKE_CXX_STANDARD 17)

set(LIBRARY_OUTPUT_PATH "${CMAKE_CURRENT_LIST_DIR}")
set(EXECUTABLE_OUTPUT_PATH "${CMAKE_CURRENT_LIST_DIR}")

# win和linux下编译选项详见：https://github.com/Samsung/netcoredbg/blob/master/compileoptions.cmake
if(WINDOWS)
    # 优先查找.lib类型的静态库
    # set(CMAKE_FIND_LIBRARY_SUFFIXES .lib ${CMAKE_FIND_LIBRARY_SUFFIXES})

    # 以下有些参数是默认的，不需要重复加，通过编译日志可以看出有哪些参数
    #https://docs.microsoft.com/en-us/cpp/build/reference/md-mt-ld-use-run-time-library?view=msvc-160
    # use the multithread, static (debug) version of the run-time library LIBCMTD.lib
    # add_compile_options($<$<OR:$<CONFIG:Release>,$<CONFIG:Relwithdebinfo>>:/MT>)
    # add_compile_options($<$<OR:$<CONFIG:Debug>,$<CONFIG:Checked>>:/MTd>)

    # add_compile_options(/W3) # set warning level to 3
    # add_compile_options(/WX) # treat warnings as errors
    # add_compile_options(/Zc:forScope) # C++ language conformance: enforce Standard C++ for scoping rules
    # add_compile_options(/source-charset:utf-8) # Force MSVC to compile source as UTF-8.
    # add_compile_options($<$<OR:$<CONFIG:Debug>,$<CONFIG:Relwithdebinfo>>:/Zi>) # enable debugging information

elseif(LINUX)
    add_compile_options(-pipe -Wall -pedantic)
endif()

if(WINDOWS)
    set(LUA_LIBRARIES deps/lua)
    set(LUA_INCLUDE_DIR deps/lua)
endif()

file(GLOB SRC_LIST "src/*.c")
add_library(pbc STATIC ${SRC_LIST})
target_include_directories(pbc PRIVATE
    pbc
)

target_include_directories(pbc PRIVATE
    "."
)

target_link_libraries(pbc PRIVATE
    lua
)

add_executable (pbctest test.cpp)

target_include_directories(pbctest PRIVATE
    "."
    ${LUA_INCLUDE_DIR}
)

target_link_directories(pbctest PRIVATE
	${LUA_LIBRARIES}
)

target_link_libraries(pbctest PRIVATE
    lua
    pbc
    stdc++fs
    dl
)

add_test(lua-protobuf_perf test test_ext.lua)
