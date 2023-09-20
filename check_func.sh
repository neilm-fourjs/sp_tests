#!/bin/bash

SRC=../
SQLSRC=sp.sql

rm -f calls calls.unused calls.used calls.only4gl calls.onlysql calls.4glfunc calls.trigger
for f in $(cat func_names.txt)
do
	echo $f
	CNTSQL=$(grep -i "[,. ]$f(" $SQLSRC | grep -v '^create ' | wc -l)
	grep -i "procedure $f" $SQLSRC | grep "^create "
	if [ $? -eq 0 ]; then
		PF=p
	else
		PF=f
	fi
	CNTTRG=$(grep -i "$f(" triggers.sql | wc -l)
	CNTFGL=$(grep -i "[,. ]$f(" $SRC/*.4gl | wc -l)
	CNTFGLF=$(grep -i "^function $f(" $SRC/*.4gl | wc -l)
	DETS="$f,$PF,,$CNTSQL,$CNTTRG,$CNTFGL,$CNTFGLF"
	echo "$DETS" >> calls
	if [ $CNTFGL -eq 0 ] && [ $CNTSQL -eq 0 ]; then
		echo "$DETS" >> calls.unused
	else
		dbschema -q -nw -f $f -d joakim | grep '.'	> sqls/$f.sql
		L=$(cat sqls/$f.sql | wc -l)
		DETS="$f,$PF,$L,$CNTSQL,$CNTTRG,$CNTFGL,$CNTFGLF"
		echo "$DETS" >> calls.used
	fi
	if [ $CNTFGL -ne 0 ] && [ $CNTFGLF -ne 0 ]; then
		echo "$DETS" >> calls.4glfunc
	fi
	if [ $CNTFGL -ne 0 ] && [ $CNTSQL -eq 0 ]; then
		echo "$DETS" >> calls.only4gl
	fi
	if [ $CNTFGL -eq 0 ] && [ $CNTSQL -ne 0 ]; then
		echo "$DETS" >> calls.onlysql
	fi
	if [ $CNTTRG -ne 0 ]; then
		echo "$DETS" >> calls.trigger
	fi
done

C1=$( cat calls | wc -l )
C2=$( cat calls.used | wc -l )
C3=$( cat calls.unused | wc -l )
C4=$( cat calls.only4gl | wc -l )
C5=$( cat calls.onlysql | wc -l )

echo "Calls: $C1 Used: $C2 Unused: $C3 Only4GL: $C4 OnlySQL: $C5"

