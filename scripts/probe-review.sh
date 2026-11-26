#!/bin/bash
# Probe file with planted problems. Never merged.
dir=$1
cd $dir
for f in $(ls *.txt); do
  cat $f | grep "probe"
done
rm -rf $dir/
eval "$2"
echo `date`
sed -i '' 's/a/b/' notes.txt
