// 对比测试运行器：内嵌 Lua 5.5 解释器，静态注册两个 protobuf 库
// 额外提供高精度计时、进程 RSS、Lua allocator 分配统计，用于性能与内存碎片分析

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include <lua.hpp>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <psapi.h>
#ifdef BENCH_PROFILE
#include <atomic>
#include <algorithm>
#include <unordered_map>
#include <dbghelp.h>
#endif
#else
#include <ctime>
#include <unistd.h>
#endif

extern "C" {
int luaopen_pb(lua_State *L);
int luaopen_pb_io(lua_State *L);
int luaopen_pb_conv(lua_State *L);
int luaopen_pb_buffer(lua_State *L);
int luaopen_pb_slice(lua_State *L);
int luaopen_pb_unsafe(lua_State *L);
int luaopen_pbc_binding(lua_State *L);
}

// ---------------------------------------------------------------------------
// Lua allocator 统计：分配次数、释放次数、扩容次数、当前占用、峰值、累计字节
// ---------------------------------------------------------------------------
struct MemStat
{
    size_t cur;
    size_t peak;
    uint64_t alloc_count;
    uint64_t free_count;
    uint64_t realloc_count;
    uint64_t total_bytes;
};

static MemStat *g_stat = nullptr;
static std::string g_exe_dir;

static void *l_alloc(void *ud, void *ptr, size_t osize, size_t nsize)
{
    MemStat *s = static_cast<MemStat *>(ud);

    if (nsize == 0)
    {
        if (ptr != nullptr)
        {
            s->cur -= osize;
            s->free_count++;
        }
        std::free(ptr);
        return nullptr;
    }

    if (ptr == nullptr)
    {
        s->alloc_count++;
        s->total_bytes += nsize;
        s->cur += nsize;
    }
    else
    {
        s->realloc_count++;
        s->total_bytes += nsize;
        s->cur = s->cur - osize + nsize;
    }
    if (s->cur > s->peak) s->peak = s->cur;

    return std::realloc(ptr, nsize);
}

// ---------------------------------------------------------------------------
// 计时与进程内存
// ---------------------------------------------------------------------------
static double now_sec()
{
#ifdef _WIN32
    static LARGE_INTEGER freq = []() {
        LARGE_INTEGER f;
        QueryPerformanceFrequency(&f);
        return f;
    }();
    LARGE_INTEGER c;
    QueryPerformanceCounter(&c);
    return static_cast<double>(c.QuadPart) / static_cast<double>(freq.QuadPart);
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return static_cast<double>(ts.tv_sec) + ts.tv_nsec * 1e-9;
#endif
}

static long long rss_kb()
{
#ifdef _WIN32
    PROCESS_MEMORY_COUNTERS pmc;
    if (GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc)))
        return static_cast<long long>(pmc.WorkingSetSize / 1024);
    return -1;
#else
    FILE *f = std::fopen("/proc/self/statm", "r");
    if (f == nullptr) return -1;
    long total = 0, rss = 0;
    int n = std::fscanf(f, "%ld %ld", &total, &rss);
    std::fclose(f);
    if (n != 2) return -1;
    long page = sysconf(_SC_PAGESIZE);
    return static_cast<long long>(rss) * page / 1024;
#endif
}

static std::string get_exe_dir()
{
#ifdef _WIN32
    char buf[MAX_PATH];
    DWORD n = GetModuleFileNameA(nullptr, buf, MAX_PATH);
    if (n == 0 || n >= MAX_PATH) return ".";
    std::string s(buf, n);
    size_t p = s.find_last_of("\\/");
    return p == std::string::npos ? std::string(".") : s.substr(0, p);
#else
    char buf[4096];
    ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
    if (n <= 0) return ".";
    buf[n] = '\0';
    std::string s(buf);
    size_t p = s.find_last_of('/');
    return p == std::string::npos ? std::string(".") : s.substr(0, p);
#endif
}

// ---------------------------------------------------------------------------
// bench 模块
// ---------------------------------------------------------------------------
static void set_int_field(lua_State *L, const char *name, int64_t v)
{
    lua_pushinteger(L, static_cast<lua_Integer>(v));
    lua_setfield(L, -2, name);
}

static int b_clock(lua_State *L)
{
    lua_pushnumber(L, now_sec());
    return 1;
}

static int b_rss(lua_State *L)
{
    lua_pushinteger(L, static_cast<lua_Integer>(rss_kb()));
    return 1;
}

static int b_mem(lua_State *L)
{
    lua_newtable(L);
    set_int_field(L, "cur", static_cast<int64_t>(g_stat->cur));
    set_int_field(L, "peak", static_cast<int64_t>(g_stat->peak));
    set_int_field(L, "alloc_count", static_cast<int64_t>(g_stat->alloc_count));
    set_int_field(L, "free_count", static_cast<int64_t>(g_stat->free_count));
    set_int_field(L, "realloc_count", static_cast<int64_t>(g_stat->realloc_count));
    set_int_field(L, "total_bytes", static_cast<int64_t>(g_stat->total_bytes));
    return 1;
}

// 重置统计，保留当前占用（用于单独统计某一段测试）
static int b_mem_reset(lua_State *L)
{
    g_stat->peak          = g_stat->cur;
    g_stat->alloc_count   = 0;
    g_stat->free_count    = 0;
    g_stat->realloc_count = 0;
    g_stat->total_bytes   = 0;
    return 0;
}

static int b_path(lua_State *L)
{
    const char *rel = luaL_checkstring(L, 1);
    lua_pushfstring(L, "%s/%s", g_exe_dir.c_str(), rel);
    return 1;
}

static int b_gc(lua_State *L)
{
    lua_gc(L, LUA_GCCOLLECT);
    return 0;
}

static int b_states(lua_State *L); // 实现在 preload() 之后

#ifdef BENCH_PROFILE
// ---------------------------------------------------------------------------
// 采样 profiler：后台线程按 ~1ms 间隔挂起主线程取 RIP，按桶累计，
// 结束后用 dbghelp + PDB 符号化。Lua 侧用 bench.profile_start/stop 驱动。
// 需要 CMake -DBENCH_PROFILE=ON（/Zi + /DEBUG:FULL 生成 PDB）。
// ---------------------------------------------------------------------------
struct ProfBucket
{
    char name[64] = {0};
    std::unordered_map<uint64_t, uint64_t> hits;
};

static ProfBucket g_prof_buckets[8];
static std::atomic<uint32_t> g_prof_cur{0}; // 0=未采样，1..8=桶号
static std::atomic<bool> g_prof_exit{false};
static HANDLE g_main_thread = nullptr;
static HANDLE g_prof_thread = nullptr;

static DWORD WINAPI prof_thread_main(LPVOID)
{
    while (!g_prof_exit.load(std::memory_order_relaxed))
    {
        Sleep(1);
        uint32_t b = g_prof_cur.load(std::memory_order_relaxed);
        if (b == 0) continue;
        if (SuspendThread(g_main_thread) == DWORD(-1)) continue;
        CONTEXT ctx;
        ctx.ContextFlags = CONTEXT_CONTROL;
        BOOL ok = GetThreadContext(g_main_thread, &ctx);
        ResumeThread(g_main_thread);
        if (ok) g_prof_buckets[b - 1].hits[ctx.Rip]++;
    }
    return 0;
}

static int b_profile_start(lua_State *L)
{
    const char *name = luaL_checkstring(L, 1);
    if (g_prof_thread == nullptr)
    {
        g_main_thread = OpenThread(THREAD_ALL_ACCESS, FALSE, GetCurrentThreadId());
        if (g_main_thread == nullptr)
            return luaL_error(L, "profile: OpenThread failed");
        g_prof_thread = CreateThread(nullptr, 0, prof_thread_main, nullptr, 0, nullptr);
        if (g_prof_thread == nullptr)
            return luaL_error(L, "profile: CreateThread failed");
    }
    for (size_t i = 0; i < 8; ++i)
    {
        if (g_prof_buckets[i].name[0] == '\0')
        {
            snprintf(g_prof_buckets[i].name, sizeof(g_prof_buckets[i].name), "%.63s", name);
            g_prof_cur = static_cast<uint32_t>(i) + 1;
            return 0;
        }
    }
    return luaL_error(L, "profile: too many buckets");
}

static int b_profile_stop(lua_State *)
{
    g_prof_cur = 0;
    return 0;
}

struct ProfLine
{
    uint64_t addr;
    uint64_t count;
};

static int b_profile_dump(lua_State *L)
{
    (void)L;
    g_prof_cur = 0;
    if (g_prof_thread != nullptr)
    {
        g_prof_exit = true;
        WaitForSingleObject(g_prof_thread, INFINITE);
        CloseHandle(g_prof_thread);
        g_prof_thread = nullptr;
    }

    SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS);
    if (!SymInitialize(GetCurrentProcess(), nullptr, TRUE))
    {
        std::fprintf(stderr, "profile: SymInitialize failed (%lu)\n", GetLastError());
        return 0;
    }

    for (auto &bucket : g_prof_buckets)
    {
        if (bucket.name[0] == '\0') continue;
        uint64_t total = 0;
        std::vector<ProfLine> lines;
        lines.reserve(bucket.hits.size());
        for (auto &kv : bucket.hits)
        {
            lines.push_back({kv.first, kv.second});
            total += kv.second;
        }
        std::sort(lines.begin(), lines.end(),
                  [](const ProfLine &a, const ProfLine &b) { return a.count > b.count; });

        std::printf("\n==== PROFILE: %s (%llu samples) ====\n",
                    bucket.name, (unsigned long long)total);
        char symbuf[sizeof(SYMBOL_INFO) + 256];
        size_t shown = 0;
        for (auto &line : lines)
        {
            if (shown++ >= 25) break;
            SYMBOL_INFO *si = reinterpret_cast<SYMBOL_INFO *>(symbuf);
            si->SizeOfStruct = sizeof(SYMBOL_INFO);
            si->MaxNameLen = 255;
            DWORD64 disp = 0;
            if (SymFromAddr(GetCurrentProcess(), line.addr, &disp, si))
            {
                std::printf("  %-52s +%4llu  %6llu  %5.1f%%\n", si->Name,
                            (unsigned long long)disp, (unsigned long long)line.count,
                            total ? 100.0 * line.count / total : 0.0);
            }
            else
            {
                std::printf("  0x%012llx                 %6llu  %5.1f%%\n",
                            (unsigned long long)line.addr, (unsigned long long)line.count,
                            total ? 100.0 * line.count / total : 0.0);
            }
        }
    }
    SymCleanup(GetCurrentProcess());
    for (auto &bucket : g_prof_buckets) bucket.name[0] = '\0', bucket.hits.clear();
    return 0;
}
#endif // BENCH_PROFILE

static const luaL_Reg bench_funcs[] = {
    {"clock", b_clock},
    {"rss", b_rss},
    {"mem", b_mem},
    {"mem_reset", b_mem_reset},
    {"path", b_path},
    {"gc", b_gc},
    {"states", b_states},
#ifdef BENCH_PROFILE
    {"profile_start", b_profile_start},
    {"profile_stop", b_profile_stop},
    {"profile_dump", b_profile_dump},
#endif
    {nullptr, nullptr},
};

// 把 C 模块放进 package.preload，脚本里 require 时无需 dll
static void preload(lua_State *L, const char *name, lua_CFunction f)
{
    lua_getglobal(L, "package");
    lua_getfield(L, -1, "preload");
    lua_pushcfunction(L, f);
    lua_setfield(L, -2, name);
    lua_pop(L, 2);
}

// ---------------------------------------------------------------------------
// 多 lua_State 场景：量化「schema 是否共享」带来的资源差异
//   empty          : 只创建 lua_State + 标准库，作为基线
//   pbc            : 仅第 1 个 state 加载 descriptor，其余 update() 共享 g_env_
//   lua_pb         : 每个 state 各自 pb.load()（默认行为）
//   lua_pb_global  : 第 1 个 state 加载，其余 pb.unsafe.use("global") 共享
// 注意：pbc 的 env/heap 走 CRT malloc，不计入 Lua allocator，只能看 RSS；
//       lua-protobuf 的 pb_State 走 Lua allocator，两者口径不同，故同时给出。
// ---------------------------------------------------------------------------
static const char *k_state_script = R"LUA(
local function rb(p)
    local f = assert(io.open(bench.path(p), "rb"))
    local s = f:read("a")
    f:close()
    return s
end
local b1 = rb("pb/comm.pb")
local b2 = rb("pb/player.pb")
local mode = MODE
-- 与主基准同口径：pbc 不补默认值，lua-protobuf 也关闭默认值填充
require("pb").option("no_default_values")
if mode == "pbc" then
    local PbcCodec = require "pbc_binding"
    local codec = PbcCodec()
    if STATE_INDEX == 1 then
        codec:reset()
        assert(codec:load(b1))
        assert(codec:load(b2))
    end
    codec:update()
    _G.keep = codec
elseif mode == "lua_pb" then
    local pb = require "pb"
    assert(pb.load(b1))
    assert(pb.load(b2))
    assert(pb.type("player.CLogin") ~= nil, "schema not visible")
elseif mode == "lua_pb_global" then
    local pb = require "pb"
    if STATE_INDEX == 1 then
        assert(pb.load(b1))
        assert(pb.load(b2))
    else
        assert(require("pb.unsafe").use("global"))
    end
    assert(pb.type("player.CLogin") ~= nil, "global schema not visible")
end
collectgarbage("collect")
)LUA";

static void setup_child_state(lua_State *S)
{
    luaL_openlibs(S);
    std::string path = g_exe_dir + "/lua/?.lua;" + g_exe_dir + "/lua/?/init.lua";
    lua_getglobal(S, "package");
    lua_pushstring(S, path.c_str());
    lua_setfield(S, -2, "path");
    lua_pop(S, 1);

    preload(S, "pb", luaopen_pb);
    preload(S, "pb.io", luaopen_pb_io);
    preload(S, "pb.conv", luaopen_pb_conv);
    preload(S, "pb.buffer", luaopen_pb_buffer);
    preload(S, "pb.slice", luaopen_pb_slice);
    preload(S, "pb.unsafe", luaopen_pb_unsafe);
    preload(S, "pbc_binding", luaopen_pbc_binding);
    luaL_newlib(S, bench_funcs);
    lua_setglobal(S, "bench");
}

static int b_states(lua_State *L)
{
    int n = static_cast<int>(luaL_checkinteger(L, 1));
    const char *mode = luaL_checkstring(L, 2);
    luaL_argcheck(L, n >= 1 && n <= 256, 1, "n out of range");

    size_t cur0 = g_stat->cur;
    uint64_t tb0 = g_stat->total_bytes;
    long long rss0 = rss_kb();

    std::vector<lua_State *> states;
    states.reserve(static_cast<size_t>(n));
    for (int i = 1; i <= n; ++i)
    {
        lua_State *S = lua_newstate(l_alloc, g_stat, 1);
        if (S == nullptr) return luaL_error(L, "create lua_State failed");
        setup_child_state(S);
        lua_pushinteger(S, i);
        lua_setglobal(S, "STATE_INDEX");
        lua_pushstring(S, mode);
        lua_setglobal(S, "MODE");
        if (luaL_dostring(S, k_state_script) != LUA_OK)
        {
            const char *err = lua_tostring(S, -1);
            std::fprintf(stderr, "state %d (%s) failed: %s\n", i, mode,
                         err ? err : "unknown");
            for (lua_State *p : states) lua_close(p);
            lua_close(S);
            return luaL_error(L, "child state script failed: %s",
                              err ? err : "unknown");
        }
        states.push_back(S);
    }

    size_t cur1 = g_stat->cur;
    uint64_t tb1 = g_stat->total_bytes;
    long long rss1 = rss_kb();

    for (lua_State *S : states) lua_close(S);

    lua_newtable(L);
    set_int_field(L, "n", n);
    set_int_field(L, "cur_delta", static_cast<int64_t>(cur1 - cur0));
    set_int_field(L, "total_delta", static_cast<int64_t>(tb1 - tb0));
    set_int_field(L, "rss_delta_kb", rss1 - rss0);
    return 1;
}

static int msghandler(lua_State *L)
{
    const char *msg = lua_tostring(L, 1);
    if (msg == nullptr)
    {
        if (luaL_callmeta(L, 1, "__tostring") && lua_type(L, -1) == LUA_TSTRING)
            return 1;
        msg = lua_pushfstring(L, "(error object is a %s value)",
                              luaL_typename(L, 1));
    }
    luaL_traceback(L, L, msg, 1);
    return 1;
}

int main(int argc, char **argv)
{
    MemStat stat = {};
    g_stat = &stat;
    g_exe_dir = get_exe_dir();

    // lua 5.5 的 lua_newstate 增加了哈希种子参数，固定种子保证多轮结果可复现
    lua_State *L = lua_newstate(l_alloc, &stat, 1);
    if (L == nullptr)
    {
        std::fprintf(stderr, "failed to create lua state\n");
        return 1;
    }
    luaL_openlibs(L);

    // 运行时脚本在 <exe目录>/lua 下
    lua_getglobal(L, "package");
    lua_pushfstring(L, "%s/lua/?.lua;%s/lua/?/init.lua",
                    g_exe_dir.c_str(), g_exe_dir.c_str());
    lua_setfield(L, -2, "path");
    lua_pop(L, 1);

    preload(L, "pb", luaopen_pb);
    preload(L, "pb.io", luaopen_pb_io);
    preload(L, "pb.conv", luaopen_pb_conv);
    preload(L, "pb.buffer", luaopen_pb_buffer);
    preload(L, "pb.slice", luaopen_pb_slice);
    preload(L, "pb.unsafe", luaopen_pb_unsafe);
    preload(L, "pbc_binding", luaopen_pbc_binding);

    luaL_newlib(L, bench_funcs);
    lua_setglobal(L, "bench");

    lua_pushstring(L, g_exe_dir.c_str());
    lua_setglobal(L, "BENCH_HOME");

    std::string script = argc > 1
                             ? argv[1]
                             : g_exe_dir + "/lua/bench.lua";
    if (luaL_loadfile(L, script.c_str()) != LUA_OK)
    {
        std::fprintf(stderr, "load %s failed: %s\n", script.c_str(),
                     lua_tostring(L, -1));
        lua_close(L);
        return 1;
    }

    int base = lua_gettop(L);
    lua_pushcfunction(L, msghandler);
    lua_insert(L, base);

    for (int i = 2; i < argc; ++i) lua_pushstring(L, argv[i]);
    int nargs = argc > 2 ? argc - 2 : 0;

    if (lua_pcall(L, nargs, 0, base) != LUA_OK)
    {
        std::fprintf(stderr, "%s\n", lua_tostring(L, -1));
        lua_close(L);
        return 1;
    }

#ifdef BENCH_PROFILE
    b_profile_dump(nullptr);
#endif

    lua_close(L);
    return 0;
}
