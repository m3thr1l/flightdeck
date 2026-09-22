#!/bin/bash
x=1
f() {
  echo "in f $1"
}
f a
for i in 1 2; do
  echo $i
done
