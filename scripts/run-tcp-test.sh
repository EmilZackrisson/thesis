#!/bin/bash

# This is made to run on NodeB (casual-lamb) only

echo "Running tcptrafficgenerator"
PKT_COUNT=1000
MIN_SIZE=10
MAX_SIZE=1420
MIN_INT_MS=1
MAX_INT_MS=1000
DEST_URL=10.200.200.1:30003
tcptrafficgenerator $PKT_COUNT $MIN_SIZE $MAX_SIZE $MIN_INT_MS $MAX_INT_MS $DEST_URL
