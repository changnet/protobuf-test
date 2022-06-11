## protobuf测试

这里主要做一些protobuf库的对比测试。所有代码都是以测试为目的，不处理异常。部分代码可能有修改，尽量让所有库的调用方式一致。

* [pbc](https://github.com/cloudwu/pbc)
1. 加了protobuf3支持
2. 使用自定义的lua binding，在decode时直接解析为原生lua table

* [lua-protobuf](https://github.com/starwing/lua-protobuf)
1. 稍微调整了下接口，允许在c发起decode

* [protolua](https://github.com/jinjiazhang/protolua)
1. 调整protolua目录为一个测试用例
2. 删掉一些第三方依赖

## 测试环境
* VirtualBox Debian 10
* GCC 8.3.0-6
* CPU AMD 5700G 3.8~4.5Ghz

## 测试结果
执行100000编码、解码。编码时，数据源为lua table，编码成功二进制数据不返回到lua(模拟直接通过socket发送)。解码时，数据源为C++中的缓存数据，解码成功返回一个lua table

每个库都执行一次Debug版本和一次Release版本测试

运行`test.sh`执行测试，不同开发环境可能需要做些调整

run debug pbc test
run 100000 times encode decode cost 0.386s
{id = 18,phone = {1 = {number = "12312341234"},2 = {type = "WORK",number = "45645674567"}},name = "ilse",email = "888888888@github.com"}
run release pbc test
run 100000 times encode decode cost 0.299s
{phone = {1 = {number = "12312341234"},2 = {type = "WORK",number = "45645674567"}},name = "ilse",id = 18,email = "888888888@github.com"}

run debug lua-protobuf test
run 100000 times encode decode cost 0.410s
{email = "888888888@github.com",name = "ilse",phone = {1 = {number = "12312341234",type = "MOBILE"},2 = {number = "45645674567",type = "WORK"}},id = 18}
run release lua-protobuf test
run 100000 times encode decode cost 0.253s
{email = "888888888@github.com",id = 18,phone = {1 = {type = "MOBILE",number = "12312341234"},2 = {type = "WORK",number = "45645674567"}},name = "ilse"}

run debug protolua test
run 100000 times encode decode cost 2.841s
{name = "ilse",phone = {1 = {type = 0,number = "12312341234"},2 = {type = 2,number = "45645674567"}},email = "888888888@github.com",id = 18}
run release protolua test
run 100000 times encode decode cost 0.743s
{name = "ilse",email = "888888888@github.com",phone = {1 = {type = 0,number = "12312341234"},2 = {type = 2,number = "45645674567"}},id = 18}

## 简单总结

`pbc`是先实现一套c接口，再实现一套lua的接口。`pbc`的lua接口没有直接使用原来的而是重新实现了一套，原因是原来的lua接口并没有直接把数据解析到
lua table，而是通过元表在访问对应的字段时解析，新实现的这套是完全把数据解析到lua table，并且代码做了调整，支持`proto3`（不支持map）。

`lua-protobuf`没有独立的c接口，而是直接实现了lua接口，完全支持`protobuf3`，测试的时候，是会设置默认值的

`protolua`则是在官方的C++ protobuf库上，利用反射实现lua接口

`pbc`和`lua-protobuf`的效率都比较高，不相上下。Debug版通过`pbc`要快一点点，但`Release`版`lua-protobuf`要快。而`protolua`的Debug版性能非常差，即使是
Release版，耗时也是前2个库的2倍左右。
