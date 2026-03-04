#!/bin/bash

# This is made to run on NodeB (casual-lamb) only

echo "Running httptrafficgenerator"
PKT_COUNT = 1000
MIN_SIZE = 200
MAX_SIZE = 2000
MIN_INT_MS = 1
MAX_INT_MS = 1000
DEST_URL = http://10.200.200.1
httptrafficgenerator $PKT_COUNT $MIN_SIZE $MAX_SIZE $MIN_INT_MS $MAX_INT_MS $DEST_URL
