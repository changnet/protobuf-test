-- 小包通信下的内存/碎片压力测试
-- 模拟真实收发：每轮新建业务 table -> 编码 -> 解码 -> 丢弃，全程不缓存对象
-- 指标来自自定义 Lua allocator 与进程工作集（RSS）

local common = require "common"

local M = {}

function M.run(libs, n)
    n = n or 100000
    common.header("2. SMALL-PACKET MEMORY / FRAGMENTATION (Heartbeat, 100k loops)")
    common.emit(string.format(
        "%-14s %12s %12s %14s %14s %14s %14s",
        "lib", "alloc/loop", "free/loop", "bytes/loop", "peak_delta(B)",
        "rss_delta(KB)", "gc_left(B)"))
    common.emit(string.rep("-", 88))

    for _, lib in ipairs(libs) do
        bench.gc()
        local rss0 = bench.rss()
        local base = bench.mem()
        bench.mem_reset()

        local seg = math.max(1, n // 4)
        local rss_trace = {}
        local sum = 0

        for i = 1, n do
            -- 每轮新建对象，模拟业务内存里的数据
            local pkt = { time = 1762000000000 + i, seq = i % 1000 }
            local buf = lib.encode("game.Heartbeat", pkt)
            local out = lib.decode("game.Heartbeat", buf)
            sum = sum + (out.seq or 0)
            if i % seg == 0 then
                rss_trace[#rss_trace + 1] = bench.rss()
            end
        end

        local m = bench.mem()
        bench.gc()
        local after = bench.mem()
        local rss1 = bench.rss()

        common.emit(string.format(
            "%-14s %12.1f %12.1f %14.1f %14d %14d %14d",
            lib.name,
            m.alloc_count / n,
            m.free_count / n,
            m.total_bytes / n,
            m.peak - base.cur,
            rss1 - rss0,
            after.cur - base.cur))
        common.emit(string.format(
            "  %-12s rss_trace(KB): %s | rss0=%d rss1=%d | sum=%d",
            lib.name, table.concat(rss_trace, " -> "), rss0, rss1, sum))
    end
end

return M
