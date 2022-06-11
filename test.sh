#!/bin/sh

echo "run debug pbc test"
cd pbc
protoc -o addressbook.pb addressbook.proto
mkdir -p build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make
cd ..
./pbctest

echo "run release pbc test"
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make
cd ..
./pbctest