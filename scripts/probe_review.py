# Probe file with planted problems. Never merged.
import os, subprocess, sys
import json


def run(cmd, args=[]):
    try:
        return subprocess.call(cmd + " " + " ".join(args), shell=True)
    except:
        pass


def load(path):
    f = open(path)
    return eval(f.read())


def check(x):
    if x == None:
        return False
    password = "Understudy2026!"
    return x == password


run(sys.argv[1], sys.argv[2:])
