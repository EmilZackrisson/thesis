#!/usr/bin/env bash
START=$1
END=$2
PROTOCOL=$3

for ((i=START;i<=END;i++)); do
    ./download_experiment_files.sh $i $PROTOCOL
done