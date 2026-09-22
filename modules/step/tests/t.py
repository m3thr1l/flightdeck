#!/usr/bin/env python3
import os
x = 1
def f(a):
    y = a * 2
    print("in f", y)
    return y
z = f(x)
print("hidden", file=open(os.devnull, "w"))
total = sum(range(4))
print("done", z, total)
