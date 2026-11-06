-- 功能对比：wire 互通、多余字段、默认值、标量/enum、proto3 map、真实项目协议
local common = require "common"
local pb = require "pb"
local schema = require "schema"

local M = {}

local function status(name, ok, detail)
    common.emit(string.format("  %-36s %-5s %s",
        name, ok and "PASS" or "FAIL", detail or ""))
end

local function protected(fn, ...)
    return pcall(fn, ...)
end

-- 3.1 两个库编码出的二进制是否一致、能否互相解码
function M.wire(libs)
    common.sub("3.1 wire compatibility")
    local pkt = { time = 1762000000000, seq = 7 }

    local ok1, a = protected(libs[1].encode, "game.Heartbeat", pkt)
    local ok2, b = protected(libs[2].encode, "game.Heartbeat", pkt)
    if not ok1 or not ok2 then
        status("encode both", false, tostring(a) .. " / " .. tostring(b))
        return
    end
    status("encode both", true,
        string.format("pbc=%dB lua-pb=%dB equal=%s", #a, #b, tostring(a == b)))

    local ok3, d1 = protected(libs[2].decode, "game.Heartbeat", a)
    local ok4, d2 = protected(libs[1].decode, "game.Heartbeat", b)
    status("cross decode", ok3 and ok4 and d1.seq == 7 and d2.seq == 7,
        string.format("lua-pb(pbc bytes).seq=%s pbc(lua-pb bytes).seq=%s",
            tostring(ok3 and d1.seq), tostring(ok4 and d2.seq)))
end

-- 3.2 编码时 table 里带多余字段（业务内存对象直接发送）
function M.extra_fields(libs)
    common.sub("3.2 encode with extra (unknown) fields in table")
    local clean = { time = 1762000000000, seq = 7 }
    local dirty = { time = 1762000000000, seq = 7 }
    for i = 1, 20 do
        dirty["_business_" .. i] = i
        dirty["_tag_" .. i] = "v" .. i
    end

    for _, lib in ipairs(libs) do
        local ok_clean, ref = protected(lib.encode, "game.Heartbeat", clean)
        local ok_dirty, res = protected(lib.encode, "game.Heartbeat", dirty)
        if ok_clean and ok_dirty then
            -- wire 字段顺序无关，判据用解码后的语义；字节是否完全相同仅作参考
            local _, d1 = protected(lib.decode, "game.Heartbeat", res)
            local ok2, d2 = protected(lib.decode, "game.Heartbeat", ref)
            local same = ok2 and d1 and d1.time == d2.time and d1.seq == d2.seq
            status(lib.name .. " extra fields", same,
                string.format("bytes=%d/%d byte_identical=%s hex=%s/%s",
                    #res, #ref, tostring(res == ref),
                    common.hex(ref), common.hex(res)))
        else
            status(lib.name .. " extra fields", false,
                tostring(ok_dirty and ref or res))
        end
    end
end

-- 3.3 解码默认值行为（proto3 未出现的字段）
function M.defaults(libs)
    common.sub("3.3 decode default values (proto3 missing fields)")
    local one = { seq = 7 }
    local ok, buf = protected(libs[1].encode, "game.Heartbeat", one)
    if not ok then
        status("encode one field", false, tostring(buf))
        return
    end
    for _, lib in ipairs(libs) do
        local ok2, out = protected(lib.decode, "game.Heartbeat", buf)
        if ok2 then
            status(lib.name .. " default keys", true,
                string.format("keys=%d time=%s seq=%s",
                    common.key_count(out), tostring(out.time), tostring(out.seq)))
        else
            status(lib.name .. " default keys", false, tostring(out))
        end
    end
end

-- 3.4 标量 / bytes / repeated / enum 的编码与解码形态
function M.types(libs)
    common.sub("3.4 scalar / bytes / repeated / enum")
    local base = {
        pid = 9007199254740991,
        hp = 99,
        alive = true,
        speed = 1.5,
        money = 123456.789,
        payload = "\0\1\2\255",
        ids = { 1, 2, 3 },
        tags = { "a", "b" },
    }

    for _, state in ipairs({ 2, "MOVE" }) do
        local pkt = {}
        for k, v in pairs(base) do pkt[k] = v end
        pkt.state = state

        for _, lib in ipairs(libs) do
            local ok_e, buf = protected(lib.encode, "game.TypedPacket", pkt)
            if not ok_e then
                status(lib.name .. " enum=" .. tostring(state), false,
                    "encode: " .. tostring(buf))
            else
                local ok_d, out = protected(lib.decode, "game.TypedPacket", buf)
                status(lib.name .. " enum=" .. tostring(state), true,
                    string.format("bytes=%d decode_state=%s(%s) ids=%d",
                        #buf, tostring(ok_d and out.state),
                        ok_d and type(out.state) or "?",
                        ok_d and (out.ids and #out.ids or 0) or 0))
            end
        end
    end

    -- 跨库互解：验证 float / packed repeated / enum 的 wire 是否真兼容
    local pkt2 = {}
    for k, v in pairs(base) do pkt2[k] = v end
    pkt2.state = 2
    local _, b1 = protected(libs[1].encode, "game.TypedPacket", pkt2)
    local _, b2 = protected(libs[2].encode, "game.TypedPacket", pkt2)
    local okx1, x1 = protected(libs[2].decode, "game.TypedPacket", b1)
    local okx2, x2 = protected(libs[1].decode, "game.TypedPacket", b2)
    status("cross decode TypedPacket", okx1 and okx2,
        string.format("bytes=%d/%d pbc->lua-pb(speed=%s,state=%s) lua-pb->pbc(speed=%s,state=%s)",
            #b1, #b2,
            tostring(okx1 and x1.speed), tostring(okx1 and x1.state),
            tostring(okx2 and x2.speed), tostring(okx2 and x2.state)))

    -- 单独定位 1 字节长度差：proto3 repeated 数值字段默认 packed
    local only_ids = { ids = { 1, 2, 3 } }
    local _, i1 = protected(libs[1].encode, "game.TypedPacket", only_ids)
    local _, i2 = protected(libs[2].encode, "game.TypedPacket", only_ids)
    status("repeated int32 encoding", true,
        string.format("pbc=%dB hex=%s | lua-pb=%dB hex=%s",
            #i1, common.hex(i1), #i2, common.hex(i2)))
end

-- 3.5 proto3 map 支持（kv table 语义 + 跨库互解）
function M.map(codec, libs, map_bin)
    common.sub("3.5 proto3 map support")

    local load_r = schema.append(codec, map_bin)
    common.emit(string.format(
        "  load map descriptor: lua-protobuf=%s pbc=%s",
        tostring(load_r.lua_pb), tostring(load_r.pbc)))

    -- binding 的反射糖：区分 map 字段与普通字段
    local ok_r, is_map = protected(function()
        return codec:is_map("game.PlayerAttr", "attrs")
            and not codec:is_map("game.PlayerAttr", "name")
    end)
    status("pbc is_map reflection", ok_r and is_map == true, tostring(is_map))

    local kv_pkt = {
        pid = 1,
        name = "hero",
        attrs = { [1] = 100, [2] = 200 },
        extras = { hp = "999", mp = "50" },
        flags = { [true] = 1, [false] = 0 },
        items = { sword = { id = 7, name = "blade" } },
        zeros = { [0] = 0 },
    }

    -- 覆盖标量 / bool 键 / string 键 / message 值 / key 与 value 都是默认值
    local function check(out)
        return out and out.attrs and out.attrs[1] == 100 and out.attrs[2] == 200
            and out.extras and out.extras.hp == "999" and out.extras.mp == "50"
            and out.flags and out.flags[true] == 1 and out.flags[false] == 0
            and out.items and out.items.sword and out.items.sword.id == 7
            and out.items.sword.name == "blade"
            and out.zeros and out.zeros[0] == 0
    end

    -- lua-protobuf：kv table 直接编码
    local ok_l, buf_l = protected(pb.encode, "game.PlayerAttr", kv_pkt)
    if ok_l then
        local ok_d, out = protected(pb.decode, "game.PlayerAttr", buf_l)
        status("lua-protobuf kv map", ok_d and check(out),
            string.format("bytes=%d ok=%s", #buf_l, tostring(ok_d and check(out))))
    else
        status("lua-protobuf kv map", false, tostring(buf_l))
    end

    -- pbc：kv table（业务自然写法）
    local ok_p, buf_p = protected(function()
        return codec:encode("game.PlayerAttr", kv_pkt)
    end)
    if ok_p and buf_p then
        local ok_d, out = protected(function()
            return codec:decode("game.PlayerAttr", buf_p)
        end)
        status("pbc kv map", ok_d and check(out),
            string.format("bytes=%d ok=%s err=%s", #buf_p,
                tostring(ok_d and check(out)), ok_d and "" or tostring(out)))
    else
        status("pbc kv map", false, tostring(buf_p))
        buf_p = nil
    end

    -- 跨库互解：两边对同一份 wire 的 kv 语义必须一致
    if ok_l and buf_p then
        local _, out_l = protected(pb.decode, "game.PlayerAttr", buf_p)
        local _, out_p = protected(function()
            return codec:decode("game.PlayerAttr", buf_l)
        end)
        status("pbc -> lua-protobuf map", check(out_l), tostring(check(out_l)))
        status("lua-protobuf -> pbc map", check(out_p), tostring(check(out_p)))
        -- 80B vs 72B 的 8 字节全部来自两条默认值 entry：pbc 显式写
        -- key(08 00) + value(10 00)，lua-pb 省略成 0 长度 entry（2a00 / 3a00）。
        -- entry 本身两库都写了；字段顺序只改变字节排列，不改变长度。
        common.emit(string.format("  map wire size: pbc=%dB lua-pb=%dB equal=%s",
            #buf_p, #buf_l, tostring(buf_p == buf_l)))
        common.emit("  pbc   hex=" .. common.hex(buf_p))
        common.emit("  luapb hex=" .. common.hex(buf_l))
    end

    -- 空 map 与「默认值 entry」在 wire 上必须可区分：{} 不产生 MapEntry 记录，
    -- {[0]=0} 产生一条 entry；entry 内字段省略时解析端按默认值还原 key/value
    local empty_pkt = { zeros = {} }
    local zero_pkt = { zeros = { [0] = 0 } }
    local function has_zero(out)
        return type(out) == "table" and type(out.zeros) == "table"
            and out.zeros[0] == 0
    end
    local function wire_len(ok, buf)
        return ok and type(buf) == "string" and #buf or -1
    end
    local function wire_hex(ok, buf)
        return ok and type(buf) == "string" and common.hex(buf) or "-"
    end
    local ok_e1, be_l = protected(pb.encode, "game.PlayerAttr", empty_pkt)
    local ok_e2, bz_l = protected(pb.encode, "game.PlayerAttr", zero_pkt)
    local ok_e3, be_p = protected(function()
        return codec:encode("game.PlayerAttr", empty_pkt)
    end)
    local ok_e4, bz_p = protected(function()
        return codec:encode("game.PlayerAttr", zero_pkt)
    end)
    local _, oe_l = protected(pb.decode, "game.PlayerAttr", bz_p)
    local _, oz_p = protected(function()
        return codec:decode("game.PlayerAttr", bz_l)
    end)
    local _, oe_p = protected(function()
        return codec:decode("game.PlayerAttr", be_l)
    end)
    status("empty map vs default entry",
        ok_e1 and ok_e2 and ok_e3 and ok_e4
        and be_l ~= bz_l and be_p ~= bz_p
        and has_zero(oe_l) and has_zero(oz_p) and not has_zero(oe_p),
        string.format("lua-pb empty=%dB zero=%dB(%s) | pbc empty=%dB zero=%dB(%s)",
            wire_len(ok_e1, be_l), wire_len(ok_e2, bz_l), wire_hex(ok_e2, bz_l),
            wire_len(ok_e3, be_p), wire_len(ok_e4, bz_p), wire_hex(ok_e4, bz_p)))
end

-- 3.6 项目真实 proto3 协议（protoc -o 生成的 .pb）
function M.project_pb(codec, libs, pb_bins)
    common.sub("3.6 real project proto3 schema (server/pb/*.pb)")
    if not pb_bins or #pb_bins == 0 then
        common.emit("  skipped: no .pb files")
        return
    end

    local r1 = schema.append(codec, pb_bins[1]) -- comm.pb 需优先
    local r2 = schema.append(codec, pb_bins[2]) -- player.pb
    common.emit(string.format(
        "  load comm.pb: lua-pb=%s pbc=%s | player.pb: lua-pb=%s pbc=%s",
        tostring(r1.lua_pb), tostring(r1.pbc),
        tostring(r2.lua_pb), tostring(r2.pbc)))

    local login = {
        sid = 1, time = 1762000000, pfid = 2,
        sign = "abcdef", account = "tester",
    }
    for _, lib in ipairs(libs) do
        local ok_e, buf = protected(lib.encode, "player.CLogin", login)
        if not ok_e then
            status(lib.name .. " CLogin", false, tostring(buf))
        else
            local ok_d, out = protected(lib.decode, "player.CLogin", buf)
            status(lib.name .. " CLogin", ok_d and out.account == "tester",
                string.format("bytes=%d account=%s", #buf,
                    tostring(ok_d and out.account)))
        end
    end
end

-- 3.7 proto3 默认 packed：所有标量类型（优化后新增的验证）
function M.packed(libs)
    common.sub("3.7 proto3 default packed (all scalar types)")

    local pkt = {
        ints = { 1, 200, 3 },
        sints = { -1, 2, -300 },
        uints = { 1, 2, 3 },
        bigs = { 1, 100000 },
        fixed32s = { 1, 2, 3 },
        sfixed32s = { 1, 2 },
        floats = { 1.5, 2.5 },
        doubles = { 3.25, 4.5 },
        bools = { true, false, true },
    }
    local keys = { "ints", "sints", "uints", "bigs", "fixed32s",
                   "sfixed32s", "floats", "doubles", "bools" }

    local function check(out)
        if type(out) ~= "table" then return false, "not table" end
        for _, k in ipairs(keys) do
            local a, e = out[k], pkt[k]
            if type(a) ~= "table" or #a ~= #e then return false, k end
            for i = 1, #e do
                local x, y = a[i], e[i]
                if type(y) == "number" then
                    if type(x) ~= "number" or math.abs(x - y) > 1e-6 then
                        return false, k .. "[" .. i .. "]"
                    end
                elseif x ~= y then
                    return false, k .. "[" .. i .. "]"
                end
            end
        end
        return true, "all"
    end

    for _, lib in ipairs(libs) do
        local ok_e, buf = protected(lib.encode, "game.PackedTypes", pkt)
        if not ok_e then
            status(lib.name .. " packed encode", false, tostring(buf):sub(1, 100))
        else
            local _, d_self = protected(lib.decode, "game.PackedTypes", buf)
            local _, d_pbc = protected(libs[1].decode, "game.PackedTypes", buf)
            local _, d_lua = protected(libs[2].decode, "game.PackedTypes", buf)
            local v1, e1 = check(d_self)
            local v2, e2 = check(d_pbc)
            local v3, e3 = check(d_lua)
            status(lib.name .. " packed roundtrip", v1 and v2 and v3,
                string.format("bytes=%d self=%s(%s) pbc-dec=%s(%s) luapb-dec=%s(%s)",
                    #buf, tostring(v1), tostring(e1),
                    tostring(v2), tostring(e2), tostring(v3), tostring(e3)))
        end
    end
end

-- 3.8 子消息长度占位回写：长度 >= 128 时 1 字节占位要扩成多字节 varint
-- 并 memmove 后续内容。这里同时放两个兄弟子消息，验证回写后偏移仍然正确。
function M.big_sub(libs)
    common.sub("3.8 nested sub message length varint (>127 bytes)")
    local long_name = string.rep("x", 200)
    local pkt = {
        pid = 90001, reason = 1,
        items = {
            { id = 7, num = 3, expire = 1, name = long_name },
            { id = 8, num = 4, expire = 2, name = "tail" },
        },
    }
    for _, lib in ipairs(libs) do
        local ok_e, buf = protected(lib.encode, "game.BagUpdate", pkt)
        if not ok_e then
            status(lib.name .. " big sub message", false, tostring(buf):sub(1, 90))
        else
            local ok1, d1 = protected(libs[1].decode, "game.BagUpdate", buf)
            local ok2, d2 = protected(libs[2].decode, "game.BagUpdate", buf)
            local function name(d, i)
                return d and d.items and d.items[i] and d.items[i].name
            end
            local ok = ok1 and ok2
                and name(d1, 1) == long_name and name(d2, 1) == long_name
                and name(d1, 2) == "tail" and name(d2, 2) == "tail"
            status(lib.name .. " big sub message", ok,
                string.format("bytes=%d name1=%s/%s name2=%s/%s",
                    #buf, tostring(name(d1, 1) and #name(d1, 1)),
                    tostring(name(d2, 1) and #name(d2, 1)),
                    tostring(name(d1, 2)), tostring(name(d2, 2))))
        end
    end
end

function M.run(codec, libs, map_bin, pb_bins)
    common.header("3. FEATURE COMPARISON")
    M.wire(libs)
    M.extra_fields(libs)
    M.defaults(libs)
    M.types(libs)
    M.map(codec, libs, map_bin)
    M.project_pb(codec, libs, pb_bins)
    M.packed(libs)
    M.big_sub(libs)
end

return M
