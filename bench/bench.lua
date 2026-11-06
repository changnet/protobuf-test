-- lua-protobuf vs 项目版 pbc 对比测试主入口
-- 运行：build/bin/bench.exe [script.lua]

local common = require "common"
local schema = require "schema"
local perf = require "perf"
local memory = require "memory"
local feature = require "feature"
local pb = require "pb"

-- pbc 不解码 proto3 默认值（缺失字段不出现在结果表里），lua-protobuf 默认会
-- 用 lpb_setdeffields 逐字段补默认值。不关掉这个行为，decode 对比相当于让
-- lua-protobuf 多做一遍填充，口径不公平。该选项是 per-lua_State 的，只影响本进程主 state。
pb.option("no_default_values")

local home = bench.path("")
local proto_dir = home .. "proto/"
local pb_dir = home .. "pb/"

common.header("0. ENVIRONMENT")
common.emit("lua               : " .. _VERSION .. " (engine/deps/lua 5.5.1)")
common.emit("pbc               : MServer fork (upstream pbc + pbc_fields) + custom lua-binding")
common.emit("lua-protobuf      : starwing/lua-protobuf (pb.c)")
common.emit("schema source     : protoc.lua (pure lua), same descriptor binary for both libs")
common.emit("build             : MSVC / CMake Release, single process, same lua state")
common.emit("bench.clock       : QueryPerformanceCounter (monotonic wall clock)")
common.emit("decode baseline   : pb.option no_default_values (aligned with pbc)")

-- 同一份 FileDescriptorSet 二进制喂给两个库
local game_bin = schema.compile(proto_dir .. "game.proto")
local types_bin = schema.compile(proto_dir .. "types.proto")
local packed_bin = schema.compile(proto_dir .. "packed.proto")
local map_bin = schema.compile(proto_dir .. "map.proto")
local codec = schema.setup({ game_bin, types_bin, packed_bin })

local libs = {
    {
        name = "pbc_binding",
        encode = function(s, t) return codec:encode(s, t) end,
        decode = function(s, b) return codec:decode(s, b) end,
    },
    {
        name = "lua-protobuf",
        encode = function(s, t) return pb.encode(s, t) end,
        decode = function(s, b) return pb.decode(s, b) end,
    },
}

-- 项目真实协议（server/pb，protoc -o 生成）
local pb_bins = {}
for _, name in ipairs({ "comm.pb", "player.pb" }) do
    local f = io.open(pb_dir .. name, "rb")
    if f then
        local s = f:read("a")
        f:close()
        pb_bins[#pb_bins + 1] = s
    end
end

perf.run(libs)
memory.run(libs, 100000)
feature.run(codec, libs, map_bin, pb_bins)

common.save(bench.path("result.txt"))
