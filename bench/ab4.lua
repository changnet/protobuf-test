-- 第 4 轮优化 A/B 专用：只测 pbc_binding，encode + decode 都测，样本数降到 1/4
-- 用法：build/bin/bench.exe <exe>/lua/ab4.lua [标签]
-- 输出形如：BagUpdate decode 12345.6 的固定行，便于多次构建之间直接比较

local common = require "common"
local schema = require "schema"
local pb = require "pb"

local home = bench.path("")
local game_bin = schema.compile(home .. "proto/game.proto")
local types_bin = schema.compile(home .. "proto/types.proto")
local codec = schema.setup({ game_bin, types_bin })

local label = arg and arg[1] or "current"

local sink = nil

local items = {}
for i = 1, 20 do
    items[i] = { id = 1000 + i, num = i, expire = 1762000000 + i, name = "item_" .. i }
end

local cases = {
    { name = "Heartbeat", schema = "game.Heartbeat", n = 200000,
      pkt = function() return { time = 1762000000000, seq = 7 } end },
    { name = "LoginReq", schema = "game.LoginReq", n = 100000,
      pkt = function()
          return { sid = 100, time = 1762000000000, account = "player_007",
                   token = "0123456789abcdef", version = 10203,
                   pos = { x = 1.5, y = 2.5, z = 3.5 }, flags = { 1, 0, 1, 1 } }
      end },
    { name = "MoveSync", schema = "game.MoveSync", n = 100000,
      pkt = function()
          return { time = 1762000000000, entity_id = 10007,
                   pos = { x = 10.25, y = 2.0, z = 30.75 }, dir = 1.57, state = 2,
                   keys = { 1, 2, 3 } }
      end },
    { name = "BagUpdate", schema = "game.BagUpdate", n = 20000,
      pkt = function() return { pid = 90001, reason = 1, items = items } end },
}

common.emit("AB4 label=" .. label)
for _, c in ipairs(cases) do
    local pkt = c.pkt()
    local buf = codec:encode(c.schema, pkt)
    local n = math.ceil(c.n / 2)
    local enc = function() sink = codec:encode(c.schema, pkt) end
    local dec = function() sink = codec:decode(c.schema, buf) end
    common.emit(string.format("%-10s encode %10.1f", c.name, common.best(enc, n, 3) * 1e9 / n))
    common.emit(string.format("%-10s decode %10.1f", c.name, common.best(dec, n, 3) * 1e9 / n))
end
common.save(bench.path("ab4_" .. label .. ".txt"))
