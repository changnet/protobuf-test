
local times = 100000

local function dump(any)
    local t = type(any)
    if "string" == t then
        return "\"" .. any .. "\""
    elseif "table" ~= t then
        return tostring(any)
    end

    local tbl = {}
    for k, v in pairs(any) do
        table.insert(tbl, string.format("%s = %s", k, dump(v)))
    end
    

    local str =  table.concat(tbl, ",")
    return "{" .. str .. "}"
end

local function test()
    local encode = pb.encode
    local decode = pb.decode
    local encode_c = pb_ext.encode
    local decode_c = pb_ext.decode
    local pack = pb.pack_msg
    local unpack = pb.unpack_msg

    local name = "ilse"
    local id = 18
    local email = "888888888@github.com"
    local phone = {
         { type = 0, number = "12312341234" },
         { type = 2,   number = "45645674567" }
      }

    local person = {
        name = name,
        id  = id,
        email = email,
        phone = phone
    }

    pb_ext.init()
    assert(pb.loadfile("addressbook.pb"))
    
    pb_ext.encode_and_save("tutorial.Person", person)

    -- ////////////////////////////////////////////////////
    local lua_buff = nil
    local lua_person = nil

    local beg_tm = os.clock ()

    for i = 1, times do
        lua_buff = encode("tutorial.Person", person)
    end

    for i = 1, times do
        lua_person = decode("tutorial.Person", lua_buff)
    end

    local end_tm = os.clock()
    print(string.format("run %d times pb with lua buffer encode decode cost %.3fs", times, end_tm - beg_tm))

    -- ////////////////////////////////////////////////////
    local s_person
    local b = pb_buffer.new()

    encode("tutorial.Person", person, b)
    local s = pb_slice.new(b:result())

    beg_tm = os.clock ()

    for i = 1, times do
        encode("tutorial.Person", person, b)
        b:reset() -- ?????
    end

    for i = 1, times do
        s_person = decode("tutorial.Person", s)
    end

    end_tm = os.clock()
    print(string.format("run %d times pb with slice encode decode cost %.3fs", times, end_tm - beg_tm))

    -- ////////////////////////////////////////////////////
    local c_person
    beg_tm = os.clock ()

    for i = 1, times do
        encode_c("tutorial.Person", person)
    end

    for i = 1, times do
        c_person = decode_c("tutorial.Person")
    end

    end_tm = os.clock()
    print(string.format("run %d times pb with c api encode decode cost %.3fs", times, end_tm - beg_tm))

    -- ////////////////////////////////////////////////////
    local u_person
    beg_tm = os.clock ()

    for i = 1, times do
        u_person = pack("tutorial.Person", name, id, email, phone)
    end

    for i = 1, times do
        name, id, email, phone = unpack("tutorial.Person", u_person)
    end

    end_tm = os.clock()
    print(string.format("run %d times pack unpack cost %.3fs", times, end_tm - beg_tm))
    -- ////////////////////////////////////////////////////
    local ub = pb_buffer.new()

    pack("tutorial.Person", ub, name, id, email, phone)
    local us = pb_slice.new(ub:result())

    beg_tm = os.clock ()

    for i = 1, times do
        pack("tutorial.Person", ub, name, id, email, phone)
        ub:reset()
    end

    for i = 1, times do
        name, id, email, phone = unpack("tutorial.Person", us)
    end

    end_tm = os.clock()
    print(string.format("run %d times pack unpack slice cost %.3fs", times, end_tm - beg_tm))
    -- ////////////////////////////////////////////////////

    print(dump(lua_person))
    print("lua dump done >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>")
    print(dump(s_person))
    print("lua slice done >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>")
    print(dump(c_person))
    print("lua c api done >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>")
    print(name, id, email, dump(phone))
end

test()

-- print(dump({a = 1, b = 5, c = "sss"}))

-- gcc -o test test.c pb.c -llua -ldl -lm
-- protoc -o addressbook.pb addressbook.proto

--[[
xzc@debian:~/code/lua-protobuf$ gcc -g -o test test.c pb.c pb_ext.c -llua -ldl -lm
xzc@debian:~/code/lua-protobuf$ ./test
run 100000 times encode decode cost 0.382s
{name = "ilse",email = "888888888@github.com",phone = {1 = {type = "MOBILE",number = "12312341234"},2 = {type = "WORK",number = "45645674567"}},id = 18}

xzc@debian:~/code/lua-protobuf$ gcc -O2 -o test test.c pb.c -llua -ldl -lm
xzc@debian:~/code/lua-protobuf$ ./test
run 100000 times encode decode cost 0.264s
{name = "ilse",email = "888888888@github.com",id = 18,phone = {1 = {type = "MOBILE",number = "12312341234"},2 = {type = "WORK",number = "45645674567"}}}

256ms / 100000 ~= 0.00256ms

测试用例
1. pack unpack 基础测试
2. pack unpack 带nil值
3. 多层嵌套message
4. map类型
5. oneof类型
6. 传入不符类型故意出错


lua_error
luaL_error
luaL_checkstack
lpb_checktable(L, f);
lpbD_checktype

typedef struct lpb_State {
    const pb_State* state;
    pb_State  local;
    pb_Cache  cache;
    pb_Buffer buffer;
    int defs_index;
    int enc_hooks_index;
    int dec_hooks_index;
    unsigned use_hooks : 1; /* lpb_Int64Mode */
    unsigned enum_as_value : 1;
    unsigned default_mode : 2; /* lpb_DefMode */
    unsigned int64_mode : 2; /* lpb_Int64Mode */
    unsigned encode_default_values : 1;
    unsigned decode_default_array : 1;
    unsigned decode_default_message : 1;
    unsigned encode_order : 1;
} lpb_State;

typedef struct lpb_Env {
    lua_State* L;
    lpb_State* LS;
    pb_Buffer* b;
    pb_Slice* s;
} lpb_Env;

error_cb放哪个结构体？？？
Env是每次都会创建，因此放lpb_State比较好一点
	只处理encode、decode过程中的错误，其他是不处理的
	检查一下其他调用，会不会导致其他功能调用改动后的函数出问题
		放Evn那就不会有这个问题，但需要每次都赋值

encode相关
void lpb_encode(lpb_Env *e, const pb_Type *t)
static void lpbE_map(lpb_Env *e, const pb_Field *f)
static void lpbE_field(lpb_Env *e, const pb_Field *f, size_t *plen)

decode相关：
int lpbD_message(lpb_Env *e, const pb_Type *t)
static void lpbD_field(lpb_Env *e, const pb_Field *f, uint32_t tag)
static void lpbD_rawfield(lpb_Env *e, const pb_Field *f)

lpb_useenchooks 这个函数调用的地方感觉有点问题，正确的用法不应该是if (e->LS->use_hooks) lpb_usedechooks(L, e->LS, t);么

pb_addvarint32等函数的返回值，完全忽略掉，作为一个基础库，这会导致用户难以查找问题

pb_type和pb_nextfield等函数均返回const类型，导致pb_sortfield需要强转

改动的函数：
lpb_encode
lpb_encode_onefield
lpbE_map
lpbE_repeated
lpbE_tagfield
lpbE_field
]]
