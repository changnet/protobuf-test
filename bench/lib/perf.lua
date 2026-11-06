-- 编解码吞吐测试：游戏服务器典型包（极小包 / 小包 / 高频位置同步 / 中等列表包）
-- 只测量库本身的 encode/decode，不把业务对象构造计入耗时

local common = require "common"

local M = {}

local sink = nil -- 防止结果被优化掉

local function mk_heartbeat(_)
    return { time = 1762000000000, seq = 7 }
end

local function mk_login(_)
    return {
        sid = 100,
        time = 1762000000000,
        account = "player_007",
        token = "0123456789abcdef",
        version = 10203,
        pos = { x = 1.5, y = 2.5, z = 3.5 },
        flags = { 1, 0, 1, 1 },
    }
end

local function mk_move(_)
    return {
        time = 1762000000000,
        entity_id = 10007,
        pos = { x = 10.25, y = 2.0, z = 30.75 },
        dir = 1.57,
        state = 2,
        keys = { 1, 2, 3 },
    }
end

local items = {}
for i = 1, 20 do
    items[i] = {
        id = 1000 + i,
        num = i,
        expire = 1762000000 + i,
        name = "item_" .. i,
    }
end

local function mk_bag(_)
    return { pid = 90001, reason = 1, items = items }
end

local cases = {
    { name = "Heartbeat", schema = "game.Heartbeat", mk = mk_heartbeat, n = 200000 },
    { name = "LoginReq", schema = "game.LoginReq", mk = mk_login, n = 100000 },
    { name = "MoveSync", schema = "game.MoveSync", mk = mk_move, n = 100000 },
    { name = "BagUpdate", schema = "game.BagUpdate", mk = mk_bag, n = 20000 },
}

-- 用第一个库（pbc_binding）编码出来的 buffer 作为两个库共同的解码输入
local function emit_row(msg, op, lib_name, size, dt, n)
    local ns = dt * 1e9 / n
    local kops = n / dt / 1000
    local mbs = size * n / dt / (1024 * 1024)
    common.emit(string.format(
        "%-11s %-7s %-14s %8d %12.1f %12.1f %10.2f",
        msg, op, lib_name, size, ns, kops, mbs))
end

function M.run(libs)
    common.header("1. ENCODE / DECODE THROUGHPUT (game server packets)")
    common.emit(string.format(
        "%-11s %-7s %-14s %8s %12s %12s %10s",
        "message", "op", "lib", "size(B)", "ns/op", "kops/s", "MB/s"))
    common.emit(string.rep("-", 88))

    for _, c in ipairs(cases) do
        local pkt = c.mk(1)
        local buf = libs[1].encode(c.schema, pkt) -- 统一 wire 输入
        local size = #buf

        for _, lib in ipairs(libs) do
            local enc = function()
                sink = lib.encode(c.schema, pkt)
            end
            local dec = function()
                sink = lib.decode(c.schema, buf)
            end

            emit_row(c.name, "encode", lib.name, size,
                common.best(enc, c.n, 3), c.n)
            emit_row(c.name, "decode", lib.name, size,
                common.best(dec, c.n, 3), c.n)
        end
    end

    -- 业务对象带多余字段时的编码开销（项目 pbc 的独有用例）
    M.run_extra_fields(libs)
end

-- 模拟"直接把业务内存对象丢给编码器"：table 里带 N 个 schema 之外的字段
function M.run_extra_fields(libs)
    common.sub("1b. ENCODE WITH EXTRA FIELDS (business object sent directly)")
    common.emit(string.format(
        "%-14s %8s %14s %14s %10s",
        "lib", "extra", "ns/op", "vs clean", "ok"))
    common.emit(string.rep("-", 88))

    local n = 100000
    for _, lib in ipairs(libs) do
        local clean_ns = nil
        for _, extra in ipairs({ 0, 20, 50 }) do
            local pkt = { time = 1762000000000, seq = 7 }
            for i = 1, extra do
                pkt["_business_" .. i] = i
            end

            local ok, err = pcall(lib.encode, "game.Heartbeat", pkt)
            if not ok then
                common.emit(string.format(
                    "%-14s %8d %14s %14s %10s",
                    lib.name, extra, "-", "-", "FAIL:" .. tostring(err):sub(1, 30)))
            else
                local fn = function()
                    sink = lib.encode("game.Heartbeat", pkt)
                end
                local ns = common.best(fn, n, 3) * 1e9 / n
                if extra == 0 then clean_ns = ns end
                common.emit(string.format(
                    "%-14s %8d %14.1f %13.2fx %10s",
                    lib.name, extra, ns, ns / clean_ns, "yes"))
            end
        end
    end
end

-- 编译参数 A/B 专用：只测 encode，样本数降到 1/5，单轮，快速比较同一口径下的耗时
function M.run_ab(libs)
    common.header("AB. ENCODE ONLY (compile-flag A/B, same schema & same table)")
    common.emit(string.format("%-11s %-14s %8s %12s",
        "message", "lib", "size(B)", "ns/op"))
    common.emit(string.rep("-", 52))
    for _, c in ipairs(cases) do
        local pkt = c.mk(1)
        local n = math.ceil(c.n / 5)
        for _, lib in ipairs(libs) do
            local fn = function() sink = lib.encode(c.schema, pkt) end
            local dt = common.best(fn, n, 1)
            common.emit(string.format("%-11s %-14s %8d %12.1f",
                c.name, lib.name, #lib.encode(c.schema, pkt), dt * 1e9 / n))
        end
    end
end

return M
