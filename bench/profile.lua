-- 采样 profile：对 pbc / lua-protobuf 的 encode、decode 各跑固定时长热循环，
-- 由 bench 的采样器记录 RIP，结束后输出热点函数排名。
-- 用法: build/bin/bench.exe lua/profile.lua [每相秒数,默认2]

local schema = require "schema"
local pb = require "pb"

local SECS = tonumber(...) or 2.0
local WARM = 0.2

local home = bench.path("")
local game_bin = schema.compile(home .. "proto/game.proto")
local codec = schema.setup({ game_bin })

-- BagUpdate：20 个子消息、编码后 437B，编解码两条路都热
local items = {}
for i = 1, 20 do
    items[i] = {
        id = 1000 + i,
        num = i,
        expire = 1762000000 + i,
        name = "item_" .. i,
    }
end
local pkt = { pid = 90001, reason = 1, items = items }

-- Heartbeat：9B / 2 字段，用于看小包（固定开销为主）的热点分布
local hb = { time = 1762000000000, seq = 7 }
local pbc_hb = assert(codec:encode("game.Heartbeat", hb))
local pb_hb = assert(pb.encode("game.Heartbeat", hb))

-- 预编码一份字节串作为解码输入（两库 wire 一致，但各自解自己的输出更贴近用法）
local pbc_bytes = assert(codec:encode("game.BagUpdate", pkt))
local pb_bytes = assert(pb.encode("game.BagUpdate", pkt))
print(string.format("profile input: BagUpdate pbc=%dB lua-pb=%dB, Heartbeat %dB, %.1fs/phase",
    #pbc_bytes, #pb_bytes, #pbc_hb, SECS))

local clock = bench.clock

-- 循环到目标时长为止，返回次数与耗时
local function run_for(fn, secs)
    local n, t0, t1 = 0, clock(), nil
    while true do
        for _ = 1, 500 do fn() end
        n = n + 500
        t1 = clock()
        if t1 - t0 >= secs then break end
    end
    return n, t1 - t0
end

local function phase(name, fn)
    run_for(fn, WARM)               -- 预热（JIT 无，但让 schema/堆/字符串驻留稳定）
    bench.profile_start(name)
    local n, dt = run_for(fn, SECS)
    bench.profile_stop()
    print(string.format("%-12s %8d ops  %8.1f ns/op", name, n, dt * 1e9 / n))
end

phase("pbc_encode", function()
    return codec:encode("game.BagUpdate", pkt)
end)

phase("pbc_decode", function()
    return codec:decode("game.BagUpdate", pbc_bytes)
end)

phase("pb_encode", function()
    return pb.encode("game.BagUpdate", pkt)
end)

phase("pb_decode", function()
    return pb.decode("game.BagUpdate", pb_bytes)
end)

phase("pbc_decode_hb", function()
    return codec:decode("game.Heartbeat", pbc_hb)
end)

phase("pb_decode_hb", function()
    return pb.decode("game.Heartbeat", pb_hb)
end)

bench.profile_dump()
