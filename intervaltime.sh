#!/bin/bash
# Change time interval on sample data files
# Doesn't change the data in any way, just tells the CAS it was collected in a different interval length

# default config/settings

NEWINT=5	#default interval retime to (5 minutes)




#start of code

function debugecho {
	dbglevel=${2:-1}
	if [ $DEBUG -ge $dbglevel ]; then techo "*** DEBUG[$dbglevel]: $1"; fi
}

function techo {
	echo -e "[`date -u`]: $1"
}

OPTS=1
while getopts ":hdi:" OPT; do
	case $OPT in
		h)
			OPTS=0
			;;
		d)
			DEBUG=$((DEBUG+1))
			;;
		i)
			OPTS=1
			NEWINT=$OPTARG
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
	echo -e "Usage: $0 [-h] [-i num]"
	echo -e "-h Show this help"
	echo -e "-i num New time interval. Default [$NEWINT]."
	exit 0
fi


debugecho "NEWINT [$NEWINT]"

if ! [ $NEWINT -eq $NEWINT ] 2> /dev/null || [ ! $NEWINT -gt 0 ] 2> /dev/null || [ ! $NEWINT -le 30 ] 2> /dev/null; then	#limit input to 1-30 minutes
	echo -e "New interval time [$NEWINT], not a valid number in range 1-30. Aborting."
	exit 1
fi



techo "$0 script"
techo "Changing interval time on samples to $NEWINT minutes"

count=0
for f in *; do
	if [ -f "$f" ] && [[ $f=~/[a-z0-9]+_[a-f0-9]{8}_[a-f0-9]+_[tb].*]/ ]] ; then
		f2=$(echo -e "$f" | awk -vnewint="`printf %x $NEWINT`" -F"_" ' /^[a-z0-9]+_[a-f0-9]{8}_[a-f0-9]+_[tb].*/ { OFS="_"; print $1,$2,newint,$4,$5 }')
		if [ "$f2" == "" ]; then debugecho "Skipping unknown file [$f]" 1; continue; fi
		if [ "$f" == "$f2" ]; then debugecho "Skipping already done file [$f}" 1; contine; fi
		count=$((count+1))
		debugecho "[$f] [$f2]" 2
		#mv "$f" "$f2"
	fi
done


techo "Completed $count files."
exit 0


