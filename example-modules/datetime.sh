#!/bin/sh
DATETIME_PID=$$
FMTS=("+%H:%M" "+%H:%M:%S" "+%Y-%m-%d")
SLEEPS=(30 1 3600)
FMT="${FMTS[0]}"
SLEEP="${SLEEPS[0]}"
INDEX=0

signal() {
    INDEX=$(($INDEX + 1 ))
    INDEX=$(($INDEX % 3 ))
    FMT="${FMTS[$INDEX]}"
    SLEEP="${SLEEPS[$INDEX]}"
}
trap signal USR1

exec 3<&0
{
    while read line
    do
        kill -USR1 $DATETIME_PID
    done <&3
} &
while true
do
    date "$FMT"
    sleep $SLEEP &
    wait $!
done
