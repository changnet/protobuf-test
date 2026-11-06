-- 编译参数 A/B 复核专用：只跑 encode 吞吐，结果写入 ab_result.txt
-- build/bin/bench.exe <exe>/lua/ab.lua

local common = require "common"
local schema = require "schema"
local perf = require "perf"
local pb = require "pb"

local home = bench.path("")
local game_bin = schema.compile(home .. "proto/game.proto")
local types_bin = schema.compile(home .. "proto/types.proto")
local codec = schema.setup({ game_bin, types_bin })

local libs = {
    { name = "pbc_binding", encode = function(s, t) return codec:encode(s, t) end },
    { name = "lua-protobuf", encode = function(s, t) return pb.encode(s, t) end },
}

perf.run_ab(libs)
common.save(bench.path("ab_result.txt"))
