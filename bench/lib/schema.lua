-- schema 装载：两个库加载同一份 FileDescriptorSet 二进制，保证 wire 层可比

local protoc = require "protoc"
local pb = require "pb"
local PbcCodec = require "pbc_binding"

local M = {}

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("a")
    f:close()
    return s
end

-- 用纯 Lua 的 protoc.lua 编译 .proto，避免依赖 protoc 二进制
function M.compile(path)
    local p = protoc.new()
    return p:compile(read_file(path), path)
end

-- 读取项目里由 protoc -o 生成的真实 .pb
function M.read_pb(path)
    return read_file(path)
end

-- 装载一批 descriptor：返回项目自研 binding 的 codec
-- pbc 的 g_env_ 是进程内静态共享的，全程只用一个 codec 实例
function M.setup(bins)
    for _, bin in ipairs(bins) do
        assert(pb.load(bin), "lua-protobuf pb.load failed")
    end

    local codec = PbcCodec()
    codec:reset()
    for _, bin in ipairs(bins) do
        assert(codec:load(bin), "pbc load failed")
    end
    codec:update()

    return codec
end

-- 追加装载 descriptor（用于 map / 真实项目协议等专项测试）
function M.append(codec, bin)
    local ok_l, err_l = pcall(function() return pb.load(bin) end)
    local ok_p, err_p = pcall(function() return codec:load(bin) end)
    return {
        lua_pb = ok_l and (err_l == true) or false,
        lua_pb_err = tostring(err_l),
        pbc = ok_p and (err_p == true) or false,
        pbc_err = tostring(err_p),
    }
end

return M
