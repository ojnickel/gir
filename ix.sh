#!/bin/bash
##cp -n .env ~/.env
git reset --hard && git pull
sleep  1
git show HEAD:gir.sh > /tmp/fix.patch
git checkout HEAD~1 -- gir.sh
git apply /tmp/fix.patch && rm -f gir.patch
echo "done"