
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

local g_name = "ilse"
local g_id = 18
local g_email = "888888888@github.com"
local g_phone = {
         { type = 0, number = "12312341234" },
         { type = 2,   number = "45645674567" }
      }

local g_person = {
      name = g_name,
      id  = g_id,
      email = g_email,
      phone = g_phone
   }

local function test()
    local encode = pb_ext.encode
    local decode = pb_ext.decode

    pb_ext.init()
    assert(pb.loadfile("addressbook.pb"))
    
    pb_ext.encode_and_save("tutorial.Person", g_person)

    local beg_tm = os.clock ()

    for i = 1, times do
        encode("tutorial.Person", g_person)
    end

    for i = 1, times do
        g_person = decode("tutorial.Person")
    end

    -- ////////////////////////////////////////////////////
    local pack = pb.pack_msg
    local unpack = pb.unpack_msg
    local end_tm = os.clock()
    print(string.format("run %d times encode decode cost %.3fs", times, end_tm - beg_tm))

    local beg_tm = os.clock ()

    for i = 1, times do
        pack("tutorial.Person", g_name, g_id, g_email, g_phone)
    end

    -- for i = 1, times do
    --     g_name, g_id, g_email, g_phone = unpack("tutorial.Person")
    -- end

    -- ////////////////////////////////////////////////////
    local end_tm = os.clock()
    print(string.format("run %d times pack unpack cost %.3fs", times, end_tm - beg_tm))
end

test()

print(dump(g_person))
print(g_name, g_id, g_email, g_phone)

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

error_cb���ĸ��ṹ�壿����
Env��ÿ�ζ��ᴴ������˷�lpb_State�ȽϺ�һ��
	ֻ����encode��decode�����еĴ��������ǲ������
	���һ���������ã��᲻�ᵼ���������ܵ��øĶ���ĺ���������
		��Evn�ǾͲ�����������⣬����Ҫÿ�ζ���ֵ

encode���
void lpb_encode(lpb_Env *e, const pb_Type *t)
static void lpbE_map(lpb_Env *e, const pb_Field *f)
static void lpbE_field(lpb_Env *e, const pb_Field *f, size_t *plen)

decode��أ�
int lpbD_message(lpb_Env *e, const pb_Type *t)
static void lpbD_field(lpb_Env *e, const pb_Field *f, uint32_t tag)
static void lpbD_rawfield(lpb_Env *e, const pb_Field *f)

lpb_useenchooks ����������õĵط��о��е����⣬��ȷ���÷���Ӧ����if (e->LS->use_hooks) lpb_usedechooks(L, e->LS, t);ô

pb_addvarint32�Ⱥ����ķ���ֵ����ȫ���Ե�����Ϊһ�������⣬��ᵼ���û����Բ�������

pb_type��pb_nextfield�Ⱥ���������const���ͣ�����pb_sortfield��Ҫǿת

�Ķ��ĺ�����
lpb_encode
lpb_encode_onefield
lpbE_map
lpbE_repeated
lpbE_tagfield
lpbE_field
]]
