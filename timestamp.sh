#!/bin/bash
# timestamp.sh
# Chris Vidler - Dyantrace DC RUM SME 2016
#
# Change start time of interval on sample data files, reuse old data.

NEWTS=${1:-}   #new interval time from first parameter - no default, 8 hex characters (epoch time)
DEBUG=0

#start of code

function debugecho {
	dbglevel=${2:-1}
	if [ $DEBUG -ge $dbglevel ]; then techo "*** DEBUG[$dbglevel]: $1"; fi
}

function techo {
	echo -e "[`date -u`]: $1"
}

OPTS=0
NOWTIME=0
while getopts ":hdt:n" OPT; do
	case $OPT in
		h)
			OPTS=0
			;;
		d)
			DEBUG=$((DEBUG+1))
			;;
		t)
			OPTS=1
			NEWTS=$OPTARG
			;;
		n)
			OPTS=1
			NOWTIME=1
			;;
		/?)
			OPTS=0
			techo "***FATAL: Invalid argument -$OPTARG."
			;;
		:)
			OPTS=0
			techo "***FATAL: argument -$OPTARG requires parameter."
			;;
	esac
done

if [ $OPTS -eq 0 ]; then
	#show help
	echo -e "Usage: $0 [-h] -t timestamp|-n"
	echo -e "-h Show this help"
	echo -e "-t timestamp Hex format epoch timestamp e.g.: 57cface0. No Default."
	echo -e "-n Change timestamps to now, accounting for interval length."
	exit 0
fi


if [ $NOWTIME == 1 ]; then
	NEWTS=0
	#generate a timestamp for 'now' account for interval length, and round up to the future.

	#get intervel length from zdata files
	INTLEN=0
	INTLEN=`ls -1 zdata* | head -n 1 | awk -F"_" ' { print $3 } '`
	if [ ! $((0x$INTLEN)) -ge 1 ] && [ ! $((0x$INTLEN)) -le 30 ]; then
		techo "***FATAL: Interval size [$INTLEN] out of range (1-30)."
		exit 1
	fi
	INTLEN=$((0x$INTLEN * 60))
	debugecho "INTLEN: [$INTLEN]"

	NOW=`date -u +%s`
	debugecho "NOW: [`printf %x $NOW`][`date -d @$NOW +'%Y-%m-%d %T'`]"
	
	NOWREM=$(($NOW / $INTLEN))
	NEWNOW=$(($INTLEN * $NOWREM))

	NEWTS=`printf %x $NEWNOW`
	debugecho "NEWTS: [$NEWTS][`date -d @$NEWNOW +'%Y-%m-%d %T'`]"
fi

if [[ ! $NEWTS=~/[a-f0-9]{8}/ ]]; then techo "invalid time stamp [$NEWTS]. aborting"; exit 1; fi

if [ $((0x$NEWTS % 60)) -gt 0 ]; then techo "invalid timestamp, not multiple fo 60 seconds. aborting"; exit 1; fi

#if [ $((0x$NEWTS)) -lt $((`date -u +%s`)) ]; then techo "timestamp in the past, probably not what you want."; fi

techo "Changing timestamp on sample files to: $NEWTS"
count=0
for f in *; do
	if [[ $f=~/[a-z0-9A-Z-%\ _]+_[0-9a-f]{8}_[a-f0-9]+_[tb][_a-z]*/ ]] ; then
		f2=$(echo -e "$f" | awk -vnewint="$NEWTS" -F"_" ' /^[a-z0-9A-Z\-% _]+_[0-9a-f]{8}_[a-f0-9]+_[tb][_a-z]*/ { OFS="_"; if (NF == 4) { print $1,newint,$3,$4; } else if (NF == 5) { print $1,newint,$3,$4,$5; } else if (NF == 6) { print $1,$2,newint,$4,$5,$6; } }')
		if [ "$f2" == "" ]; then debugecho "Skipping unknown file [$f]" 2; continue; fi
		if [ "$f" == "$f2" ]; then debugecho "Skipping existing file [$f]"; continue; fi
		count=$((count+1))
		debugecho "[$f] [$f2]" 2
		mv "$f" "$f2"
    fi
done

techo "Completed $count files"

