local person
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
    local encode = pb_ext.encode
    local decode = pb_ext.decode

   local data = {
      name = "ilse",
      id  = 18,
      email = "888888888@github.com",
      phone = {
         { type = 0, number = "12312341234" },
         { type = 2,   number = "45645674567" }
      }
   }

    pb_ext.init()
    assert(pb_ext.load("addressbook.pb"))
    
    pb_ext.encode_and_save("tutorial.Person", data)

    local beg_tm = os.clock ()

    for i = 1, times do
        encode("tutorial.Person", data)
    end

    for i = 1, times do
        person = decode("tutorial.Person")
    end

    -- ////////////////////////////////////////////////////
    local end_tm = os.clock()
print(string.format("run %d times encode decode cost %.3fs", times, end_tm - beg_tm))	
end



test()



print(dump(person))
-- print(dump({a = 1, b = 5, c = "sss"}))

-- gcc -o test test.c pb.c -llua -ldl -lm
-- protoc -o addressbook.pb addressbook.proto

--[[
xzc@debian:~/code/lua-protobuf$ gcc -o test test.c pb.c -llua -ldl -lm
xzc@debian:~/code/lua-protobuf$ ./test
run 100000 times encode decode cost 0.382s
{name = "ilse",email = "888888888@github.com",phone = {1 = {type = "MOBILE",number = "12312341234"},2 = {type = "WORK",number = "45645674567"}},id = 18}

xzc@debian:~/code/lua-protobuf$ gcc -O2 -o test test.c pb.c -llua -ldl -lm
xzc@debian:~/code/lua-protobuf$ ./test
run 100000 times encode decode cost 0.264s
{name = "ilse",email = "888888888@github.com",id = 18,phone = {1 = {type = "MOBILE",number = "12312341234"},2 = {type = "WORK",number = "45645674567"}}}

256ms / 100000 ~= 0.00256ms
]]
