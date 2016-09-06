#!/bin/bash
# AMD Sample Aggregation Script
# Chris Vidler - Dyantrace DC RUM SME 2016
#
# Aggregate a large number of interval data into one interval
#
# Can't do ADS data files, as many of them are binary databases
#

#defaults
SOURCEPATH="/var/spool/adlex/rtm/"
DESTPATH="`mktemp -d -t aggs.XXXXXXXX`"
DEBUG=0


#config/settings
OPTS=0
while getopts ":dhs:o:b:c:" OPT; do
	case $OPT in
		h)
			OPTS=0
			;;
		d)
			DEBUG=$((DEBUG+1))
			;;
		s)
			OPTS=1
			SOURCEPATH=$OPTARG
			;;
		o)
			DESTPATH=$OPTARG
			;;
		b)
			#begin timestamp
			OPTS=1
			BTS=$OPTARG
			;;
		c)
			#num of samples to agg (count)
			OPTS=1
			TSC=$OPTARG
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
	echo -e "Usage: $0 [-h] -s sourcepath [-o outputpath] -b hexts -c count"
	echo -e "-h Show this help"
	echo -e "-s Source path for files to aggregate"
	NOW=`date -u +%s`
	echo -e "-b hexts Begin timestamp - UTC unix timestamp in hex e.g. '`printf %x $NOW`'"
	echo -e "   incorrect timestamps will be rounded down to nearest interval tiemstamp"
	echo -e "-c count Number of samples/intervals to aggregate"
	echo -e "-o outputpath Destination to save aggregated sample. Default [$DESTPATH]."
	rm -rf $DESTPATH
	exit 0
fi


#start of code

function debugecho {
	dbglevel=${2:-1}
	if [ $DEBUG -ge $dbglevel ]; then techo "*** DEBUG[$dbglevel]: $1"; fi
}

function techo {
	echo -e "[`date -u`]: $1"
}


#check source path
#SOURCEPATH=$(printf %q $SOURCEPATH)
if [ ! -d "$SOURCEPATH" ] || [ ! -r "$SOURCEPATH" ]; then
	techo "***FATAL: Source path: $SOURCEPATH unreadable."
	exit 1
fi

#check dest path
if [ ! -w "$DESTPATH" ]; then
	techo "***FATAL: Destination path [$DESTPATH] unwriteable."
	exit 1
fi

#grab list of unique data file types
TYPES=`ls -1 "$SOURCEPATH" | awk -F"_" ' /^[a-z]+_[a-f0-9]{8}_[a-f0-9]+_[tb].*/ { OFS="_"; print $1,"*",$3,$4,$5 } ' | sort | uniq`

#determine data interval length 1-30 minutes, zdata file name tells us
INTLEN=0
INTLEN=`ls -1 "$SOURCEPATH"/zdata* | head -n 1 | awk -F"_" ' { print $3 } '`
if [ ! 0x$INTLEN -ge 1 ] && [ ! 0x$INTLEN -le 30 ]; then
	techo "***FATAL: Interval size [$INTLEN] out of range (1-30)."
	exit 1
fi

debugecho "SOURCEPATH: [$SOURCEPATH], DESTPATH: [$DESTPATH]"
debugecho "BTS: [$BTS], TSC: [$TSC]"
debugecho "INTLEN: [$INTLEN], TYPES=[$TYPES] "

#debug: output each file type
#echo "Types: [$TYPES]"
#echo "$TYPES" | while read -r FTYPE; do
#   echo -e "[$FTYPE]"
#done;

TOT="$(($TSC*0x$INTLEN))"
techo "Aggregating $TSC Samples ($TOT minutes) to: [$DESTPATH]"


#build list of requested timestamps
#subinterval is always 1 minute (used for amddata, diagdata)
#interval is configurable, determined above.
#first determine proper starting timestamp (confirm user input, round down if not a valid timestamp and check data exists)
debugecho "User input BTS: [$BTS]"
REM=$((0x$INTLEN * 60))
REM=$((0x$BTS % $REM))
debugecho "REM: [$REM]"
BTS=`printf %x $((0x$BTS - $REM))`
debugecho "Corrected BTS: [$BTS]"

#count files with starting timestamp, see if there's any there.
FC=`ls -1 "${SOURCEPATH}"/zdata_${BTS}_* | wc -l`
debugecho "FS: [$FC]"

if [ $FC -eq 0 ]; then
	techo "***FATAL: No data with starting timestamp found."
	exit 1
fi

#iterate to create all applicable timestamps
INTLIST=""
SINTLIST=""
step=$((0x$INTLEN*60))
int=0
for INC in `seq 0 $((TSC-1))`; do
	int=$((step*INC))
	int=`printf %x $((0x${BTS} + $int))`
	INTLIST="${INTLIST}$int\n"
done
debugecho "INTLIST: [$INTLIST]"

#build subinterval timestamp list
if [ 0x$INTLEN -gt 1 ]; then
	for INC in `seq 0 $((TOT-1))`; do
		int=$((60*INC))
		int=`printf %x $((0x${BTS} + $int))`
		SINTLIST="${SINTLIST}$int\n"
	done
fi
debugecho "SINTLIST: [$SINTLIST]"

#all tests/setup complete
#exit

#start aggregating
echo "$TYPES" | while read -r FTYPE; do
	if [[ $FTYPE == *"_b_"* ]]; then debugecho "Skipping binary file type [$FTYPE]" 3; continue; fi         # skip binary file types
	techo "Aggregating file type: [$FTYPE]"
	COUNT=0
	for FILE in "$SOURCEPATH"/$FTYPE; do
		TS=${FILE##*/}
		TS=${TS#*_}
		TS=${TS%%_*}
		debugecho "TS: [$TS]" 3
		if [[ ! $SINTLIST =~ $TS ]]; then debugecho "Skipping FILE: [$FILE], not in timestamp list" 3; continue; fi

		debugecho "Processing file [$FILE]" 2
		COUNT=$((COUNT + 1))
		if [ $COUNT -eq 1 ]; then
			#for the first file, generate destination name (grab the first timestamp)
			#TS=`echo -e "${FILE##*/}" | grep -Eo "([a-f0-9]{8})" `
			debugecho "Starting Timestamp: [$BTS]" 3
			DESTFILE="$DESTPATH/$FTYPE"
			DESTFILE="${DESTFILE/\*/$BTS}"
			debugecho "DESTFILE: [$DESTFILE]" 3
			#dump contents of first file to the destination file
			cat "$FILE" > "$DESTFILE"
			#skip the rest of this loop
			continue
		fi
		#dump the contents (minus the headers) to the destination file
		grep -v "^#" "$FILE" >> "$DESTFILE"
	done;
	techo "Aggregated [$COUNT] files to [$DESTFILE]"
done;

techo "Samples aggregated to: [$DESTPATH]"
exit 0

