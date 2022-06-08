## protobuf测试

这里主要做一些protobuf库的对比测试。所有代码都是以测试为目的，不处理异常。部分代码可能有修改，尽量让所有库的调用方式一致。

* [pbc](https://github.com/cloudwu/pbc)
1. 加了protobuf3支持
2. 使用自定义的lua binding，在decode时直接解析为原生lua table

* [lua-protobuf](https://github.com/starwing/lua-protobuf)
1. 稍微调整了下接口，允许在c发起decode
