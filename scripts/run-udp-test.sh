#!/bin/bash

myexpid=$EXPID;
myrunid=$RUNID;
mykeyid=$KEYID;

eval "$1"

SERVER=${server:-10.1.0.1}
minIfg=${minIfg:-0}
maxIfg=${maxIfg:-100000}
waitDistrib=${wtDist:-d}

minSize=${minSize:-64}
maxSize=${maxSize:-1460}
pktDistrib=${pktDist:-d}

pkts=${pktCount:-10000}
samples=${samples:-1}
dport=${destPort:-7}


echo "udpclient -e $myexpid -r $myrunid -k $mykeyid -s $SERVER --port $dport -l $minSize -L $maxSize -m $pktDistrib -w $minIfg -W $maxIfg -v $waitDistrib -n $pkts "
udpclient -e $myexpid -r $myrunid -k $mykeyid -s $SERVER --port $dport -l $minSize -L $maxSize -m $pktDistrib -w $minIfg -W $maxIfg -v $waitDistrib -n $pkts

echo "SUCCESS"