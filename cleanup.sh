#!/bin/bash

cd "$1"

rm -rf b1 b2 images packages targets

mv source1/dl ./

cd source1
make distclean

cd ..
mv source1 source

cd source2
make distclean
cd ..
rm -rf source2 

mv dl source/

echo -e "\n clean have finished\n"
