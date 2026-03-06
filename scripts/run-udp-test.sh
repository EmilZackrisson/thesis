#!/bin/bash

echo "Running UDP testing"

udpclient -s 10.200.200.1 -p 30002 -n 100 -i 100000 -e 1 -r 1 -k 1