-- 瓶颈定位：把 encode 成本拆成固定开销 / 每字段遍历 / 每字节拷贝 / 子消息 / 输出拷贝
-- 独立运行：build/bin/bench.exe <exe>/lua/probe.lua

local common = require "common"
local schema = require "schema"
local pb = require "pb"

local home = bench.path("")
local bin = schema.compile(home .. "proto/probe.proto")
local codec = schema.setup({ bin })

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

local sink = nil

local function ns(fn, n)
    return common.best(fn, n, 3) * 1e9 / n
end

-- 最小二乘拟合 T(n) = a + b*n
local function fit(pts)
    local n, sx, sy, sxx, sxy = #pts, 0, 0, 0, 0
    for _, p in ipairs(pts) do
        sx = sx + p[1]; sy = sy + p[2]
        sxx = sxx + p[1] * p[1]; sxy = sxy + p[1] * p[2]
    end
    local d = n * sxx - sx * sx
    local b = (n * sxy - sx * sy) / d
    return (sy - b * sx) / n, b
end

local function row(fmt, ...)
    common.emit(string.format(fmt, ...))
end

common.header("A. FIXED COST: encode empty table (no field traversal)")
row("%-14s %14s %14s", "lib", "ns/op", "bytes")
row("%s", string.rep("-", 46))
for _, lib in ipairs(libs) do
    local empty = {}
    local t = ns(function() sink = lib.encode("probe.Scalars", empty) end, 200000)
    local b = lib.encode("probe.Scalars", empty)
    row("%-14s %14.1f %14d", lib.name, t, #b)
end

common.header("B. PER-FIELD COST: 1..32 int32 fields (linear fit)")
row("%-14s %10s %14s %14s %14s", "lib", "fields", "ns/op", "bytes", "delta-ns")
row("%s", string.rep("-", 70))
local fits = {}
for _, lib in ipairs(libs) do
    fits[lib.name] = {}
    local prev = nil
    for _, n in ipairs({ 1, 2, 4, 8, 16, 32 }) do
        local pkt = {}
        for i = 1, n do pkt["f" .. i] = 12345 + i end
        local t = ns(function() sink = lib.encode("probe.Scalars", pkt) end, 100000)
        local b = lib.encode("probe.Scalars", pkt)
        table.insert(fits[lib.name], { n, t })
        row("%-14s %10d %14.1f %14d %14s", lib.name, n, t, #b,
            prev and string.format("%.1f", t - prev) or "-")
        prev = t
    end
end
row("%s", string.rep("-", 70))
for _, lib in ipairs(libs) do
    local a, b = fit(fits[lib.name])
    row("fit %-10s fixed=%.1f ns  per_field=%.1f ns", lib.name, a, b)
end

common.header("C. PER-BYTE COST: bytes payload 0..4096 (realloc + memcpy)")
row("%-14s %10s %14s %14s", "lib", "bytes", "ns/op", "wire")
row("%s", string.rep("-", 56))
for _, lib in ipairs(libs) do
    for _, len in ipairs({ 0, 16, 64, 256, 1024, 4096 }) do
        local pkt = { data = string.rep("x", len) }
        local t = ns(function() sink = lib.encode("probe.Blob", pkt) end, 50000)
        row("%-14s %10d %14.1f %14d", lib.name, len, t, #lib.encode("probe.Blob", pkt))
    end
end

common.header("D. SUB-MESSAGE COST: 1..64 nested Child")
row("%-14s %10s %14s %14s", "lib", "children", "ns/op", "wire")
row("%s", string.rep("-", 56))
for _, lib in ipairs(libs) do
    for _, n in ipairs({ 1, 4, 16, 64 }) do
        local pkt = { items = {} }
        for i = 1, n do pkt.items[i] = { id = i, v = i * 2 } end
        local t = ns(function() sink = lib.encode("probe.Nest", pkt) end, 30000)
        row("%-14s %10d %14.1f %14d", lib.name, n, t, #lib.encode("probe.Nest", pkt))
    end
end

common.header("E. OUTPUT COPY: pbc encode() vs encode_to_buffer() (zero-copy)")
row("%-24s %10s %14s %14s", "lib/api", "fields", "ns/op", "bytes")
row("%s", string.rep("-", 66))
for _, n in ipairs({ 1, 8, 32 }) do
    local pkt = {}
    for i = 1, n do pkt["f" .. i] = 12345 + i end
    local a = ns(function() sink = codec:encode("probe.Scalars", pkt) end, 100000)
    local z = ns(function()
        local p, len = codec:encode_to_buffer("probe.Scalars", pkt)
        sink = len
    end, 100000)
    local b = ns(function() sink = pb.encode("probe.Scalars", pkt) end, 100000)
    row("%-24s %10d %14.1f %14s", "pbc encode()", n, a, "-")
    row("%-24s %10d %14.1f %14s", "pbc encode_to_buffer()", n, z,
        string.format("copy=%.1f", a - z))
    row("%-24s %10d %14.1f %14s", "lua-protobuf encode()", n, b, "-")
end

common.header("F. ALLOCATION PER ENCODE (GC stopped, Lua allocator only)")
row("%-14s %12s %12s %14s %14s", "lib", "alloc/op", "realloc/op", "bytes/op", "cur-delta")
row("%s", string.rep("-", 72))
local n = 20000
local pkt = {}
for i = 1, 16 do pkt["f" .. i] = 12345 + i end
for _, lib in ipairs(libs) do
    bench.gc()
    collectgarbage("stop")
    bench.mem_reset()
    local cur0 = bench.mem().cur
    for _ = 1, n do sink = lib.encode("probe.Scalars", pkt) end
    local m = bench.mem()
    collectgarbage("restart")
    row("%-14s %12.2f %12.2f %14.1f %14d", lib.name,
        m.alloc_count / n, m.realloc_count / n, m.total_bytes / n,
        m.cur - cur0)
end

common.header("G. DECODE PER-FIELD COST: 1..32 int32 fields (linear fit)")
row("%-14s %10s %14s %14s %14s", "lib", "fields", "ns/op", "bytes", "delta-ns")
row("%s", string.rep("-", 70))
local gfit = {}
for _, lib in ipairs(libs) do
    gfit[lib.name] = {}
    local prev = nil
    for _, n in ipairs({ 1, 2, 4, 8, 16, 32 }) do
        local pkt = {}
        for i = 1, n do pkt["f" .. i] = 12345 + i end
        local buf = lib.encode("probe.Scalars", pkt)
        local t = ns(function() sink = lib.decode("probe.Scalars", buf) end, 100000)
        table.insert(gfit[lib.name], { n, t })
        row("%-14s %10d %14.1f %14d %14s", lib.name, n, t, #buf,
            prev and string.format("%.1f", t - prev) or "-")
        prev = t
    end
end
row("%s", string.rep("-", 70))
for _, lib in ipairs(libs) do
    local a, b = fit(gfit[lib.name])
    row("fit %-10s fixed=%.1f ns  per_field=%.1f ns", lib.name, a, b)
end

common.save(bench.path("probe_result.txt"))
