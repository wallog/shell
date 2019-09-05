#!/usr/bin/env bash
#wl
set -u

function getThread(){
    ps -mp $1 -o THREAD,tid| sort -nr | head -2 |tail -1| awk '{print $NF}'
}

function getPIDHex(){
    printf "%x\n" $(getThread $1)
}

function getStack(){
    jstack $1 | grep -C 15 $(getPIDHex $1)
}

function judgeCmd(){
    type $1 &>/dev/null
    if [[ $? -ne 0 ]];then
        echo "Cmd: $1 inexistence!"
        exit 2
    fi
}

if [[ $# -eq 0 || "$1" == "-h" ]];then
    echo "usage:"
    echo "    $0 pid"
    exit
fi

pid=$1
tid=$(getThread ${pid})
hex=$(getPIDHex ${pid})

judgeCmd "jstack"

echo "cpu usage highest thread is: $(getThread ${pid})"
echo "thead Hex is: $(getPIDHex ${pid})"

getStack ${pid}
