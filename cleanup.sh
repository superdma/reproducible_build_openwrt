#!/bin/bash

cd "$1"

rm -rf b1 b2 images packages

rsync -av source1/dl/ dl/

cd source1
make distclean

cd ..
mv source1 source

cd source2
make distclean
cd ..
rm -rf source2

echo -e "\n clean have finished\n"
