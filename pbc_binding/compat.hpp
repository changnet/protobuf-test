#pragma once

#include <cassert>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <string>

// 与引擎 global/global.hpp 对齐的最小兼容层
// 目的：让项目里自研的 PbcCodec 不依赖引擎整体，可独立编进对比工程
// 规则：出错禁止静默返回，统一打日志到 stderr

inline void pbc_log_error(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    std::fprintf(stderr, "[pbc_binding] ");
    std::vfprintf(stderr, fmt, ap);
    std::fprintf(stderr, "\n");
    va_end(ap);
}

inline std::string pbc_std_fmt(const char *fmt, ...)
{
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    int n = std::vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);

    if (n < 0) return std::string("format error");
    if (static_cast<size_t>(n) < sizeof(buf)) return std::string(buf, n);

    // 极少数超长信息按需扩容，避免截断
    std::string out;
    out.resize(static_cast<size_t>(n) + 1);
    va_start(ap, fmt);
    std::vsnprintf(&out[0], out.size(), fmt, ap);
    va_end(ap);
    out.resize(static_cast<size_t>(n));
    return out;
}

#define ELOG pbc_log_error
#define STD_FMT pbc_std_fmt
