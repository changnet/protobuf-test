-- 通用输出与计时工具
-- 输出统一为 ASCII，避免 Windows 控制台代码页干扰数据采集

local M = {}

local lines = {}

-- 输出一行并留档
function M.emit(line)
    lines[#lines + 1] = line
    print(line)
end

function M.header(title)
    M.emit("")
    M.emit(string.rep("=", 88))
    M.emit(title)
    M.emit(string.rep("=", 88))
end

function M.sub(title)
    M.emit("")
    M.emit("-- " .. title)
end

function M.save(path)
    local f = assert(io.open(path, "wb"))
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
    M.emit("[result saved to] " .. path)
end

-- 多轮取最小耗时；每轮前全量 GC，消除 GC 相位差对两个库的影响
function M.best(fn, n, rounds)
    rounds = rounds or 3
    fn() -- 预热
    local best = math.huge
    for _ = 1, rounds do
        bench.gc()
        local t0 = bench.clock()
        for _ = 1, n do fn() end
        local dt = bench.clock() - t0
        if dt < best then best = dt end
    end
    return best
end

-- 十六进制，用于对比 wire 字节
function M.hex(s)
    return (s:gsub(".", function(c)
        return string.format("%02x", c:byte())
    end))
end

-- 统计 table 的 key 数量（不依赖 #，兼容 lua 5.5 的稀疏表）
function M.key_count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

return M
