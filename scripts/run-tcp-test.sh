#!/bin/bash

# This is made to run on NodeB (casual-lamb) only

echo "Starting tcpserver"
tcpserver -e $EXP_ID -r $RUN_ID -k $KEY_ID -p 30002 &

echo "Starting tcpclient"
tcpclient -e $EXP_ID -r $RUN_ID -k $KEY_ID --server 10.200.200.1 -p 30002 -n 100 --pktsize b --wait e

# echo "Starting tcpserver"; tcpserver -e $EXP_ID -r $RUN_ID -k $KEY_ID -p 30002 &; echo "Starting tcpclient"; tcpclient -e $EXP_ID -r $RUN_ID -k $KEY_ID --server 10.200.200.1 -p 30002 -n 100 --pktsize b --wait e; echo "SUCCESS"