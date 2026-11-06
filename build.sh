#!/usr/bin/env bash
# lua-protobuf 与项目版 pbc 对比工程的一键脚本（Debian 12）
# 与 build.bat 等价：configure(Release) -> build -> 可选运行 bench，源码树不产生文件。
# Linux 产物放在 build/linux 下，与 Windows 版 build/ 的 Ninja 缓存隔离：
# 共享目录里两者会同时存在，而 CMakeCache.txt 记录了绝对路径和编译器，不能跨平台复用。
# 用法：./build.sh [run|test]，run/test 后的附加参数原样传给 bench。

set -euo pipefail
trap 'echo "[build.sh] 第 ${LINENO} 行执行失败" >&2' ERR

cd "$(dirname "$0")"

# 入口校验：参数只允许 run / test / 空
case "${1:-}" in
    run|test|"") ;;
    *)
        echo "[build.sh] 未知参数: $1（仅支持 run / test）" >&2
        exit 1
        ;;
esac

# 入口校验：Debian 12 需要 cmake 与 build-essential（make/g++），脚本不代装软件
for tool in cmake make c++; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[build.sh] 缺少 $tool，请先执行: sudo apt install cmake build-essential" >&2
        exit 1
    fi
done

build_dir="${BENCH_BUILD_DIR:-build/linux}"

# Debian 12 自带 make，不强依赖 ninja；优化级别与 build.bat 一样由 Release 统一提供
# （MSVC 为 /O2 /Ob2 /DNDEBUG，GCC 为 -O3 -DNDEBUG，四个 target 完全一致）
cmake -S . -B "$build_dir" -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release
cmake --build "$build_dir" --parallel "$(nproc)"

if [ "${1:-}" != "" ]; then
    shift
    "$build_dir/bin/bench" "$@"
fi
