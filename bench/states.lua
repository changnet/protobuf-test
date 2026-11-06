-- 多 lua_State 资源对比：pbc 共享 env vs lua-protobuf per-state schema
-- 独立运行：build/bin/bench.exe <exe>/lua/states.lua

local common = require "common"

local modes = { "empty", "pbc", "lua_pb", "lua_pb_global" }
local counts = { 1, 8, 32 }

local function row(fmt, ...)
    common.emit(string.format(fmt, ...))
end

common.header("G. MULTI LUA-STATE RESOURCE (schema sharing)")
common.emit("pbc env/heap uses CRT malloc -> visible in RSS only; lua-protobuf pb_State uses Lua allocator -> visible in cur")
row("%-16s %6s %14s %14s %12s", "mode", "n", "cur_delta(B)", "total_delta(B)", "rss_delta(KB)")
row("%s", string.rep("-", 70))

local data = {}
for _, n in ipairs(counts) do
    for _, mode in ipairs(modes) do
        local r = bench.states(n, mode)
        data[mode .. ":" .. n] = r
        row("%-16s %6d %14d %14d %12d", mode, n,
            r.cur_delta, r.total_delta, r.rss_delta_kb)
    end
    row("%s", string.rep("-", 70))
end

common.header("G2. NET SCHEMA COST (subtract empty-state baseline)")
row("%-16s %6s %16s %16s", "mode", "n", "net_cur(B)", "net_rss(KB)")
row("%s", string.rep("-", 56))
for _, n in ipairs(counts) do
    local base = data["empty:" .. n]
    for _, mode in ipairs({ "pbc", "lua_pb", "lua_pb_global" }) do
        local r = data[mode .. ":" .. n]
        row("%-16s %6d %16d %16d", mode, n,
            r.cur_delta - base.cur_delta,
            r.rss_delta_kb - base.rss_delta_kb)
    end
end

common.save(bench.path("states_result.txt"))
