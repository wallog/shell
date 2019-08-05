#!/bin/bash

set -e

#瀛洲斁CSV鐩綍,partiton鏂囦欢,鏍规嵁瀹為檯鎯呭喌淇敼鐩綍锛侊紒
table_name=KM_TEST
csv_dir=/root/csv_dir
partxt=partition
parsql=partition.sql
num=1
tmp_dir=$csv_dir/tmp
[ ! -d $csv_dir ] && mkdir -p $csv_dir
[ ! -d $tmp_dir ] && mkdir -p $tmp_dir

echo -e "select partition_name from dba_tab_partitions where table_name='$table_name';\nexit" > $csv_dir/$parsql

#鐢熸垚partition鏂囦欢,鏍规嵁瀹為檯鎯呭喌淇敼鐧诲綍鐢ㄦ埛鍜屽瘑鐮侊紒锛?
ext="sqlplus64 sys/oracle@192.168.10.29/kmtest as sysdba"

#鏍规嵁瀹為檯鎯呭喌淇敼姝ｅ垯琛ㄨ揪寮忥紒锛?
for n in $(seq 2012 2018);do
    $ext @$csv_dir/$parsql |grep "^P.*$n.*" > $csv_dir/$partxt$n
if [ $? != 0 ];then
    echo "sql璇彞鏈夐棶棰橈紒"
    exit 23
fi
#1,璇诲彇partition鏂囦欢锛屽苟鐢熸垚sql鏂囦欢
#2,鎸夌収sql鏂囦欢鐢熸垚csv鏂囦欢

for pt in $(cat $csv_dir/$partxt$n);do
echo "set linesize 50;
set pagesize 0;
set feedback off;
set echo off;
set numwidth 20;
set newp none;
set trispool on;
alter session set nls_date_format='yyyy-mm-dd';
spool $tmp_dir/$pt.csv;
select '\"USER_ID\",\"USER_NAME\",\"REGIST_TIME\"' from dual;
select '\"' ||USER_ID||'\",\"'||USER_NAME||'\",\"'||REGIST_TIME||'\"' from km_test partition($pt);
spool off
exit" > $csv_dir/$pt.sql
create table wltest("NO" char, "KIND_NAME" char, "PERIOD_NAME" char, "RATE_VALUE" char, "ACTIVE_DATE" char, "BZ" char);
create table km("BRNO" char,"KMH" char,"BZ" char,"ACTDATE" char,"BAL" char,"JAMOUNT" char,"DAMOUNT" char,"FLAG_DATE" char)
$ext @$csv_dir/$pt.sql &>/dev/null

if [ $? != 0 ];then
    #濡傛灉鏈夐敊璇病鐢熸垚鐨凜SV鏂囦欢锛屾煡鐪媤rong_csv.tst鏂囦欢锛侊紒
    echo "$pt.sql is wrong" >> $csv_dir/wrong_csv.txt

else
    echo " $num $pt.csv is successful!!"
    ((num+=1))
fi

done

echo "===================================="
echo ""
#灏嗙敓鎴愮殑CSV鏂囦欢绉诲姩鍒癈SV鐩綍

mkdir -p $csv_dir/csv.$n && cd $tmp_dir && mv *.csv ../csv.$n

#缁熻姣忎釜CSV鏂囦欢鐨勮鏁?echo "姣忎釜CSV鏂囦欢鐨勮鏁板拰鎬绘暟锛?
cd $csv_dir/csv.$n && wc -l *.csv
#鍚堝苟瀵煎嚭鐨凜SV鏂囦欢
sed -n '1p' $(ls ./ |awk '{print $1}' |head -1) > $csv_dir/$table_name.$n.csv

for cf in $(ls $csv_dir/csv.$n);do

cd $csv_dir/csv.$n && sed -n '2,$p' $cf >> $csv_dir/$table_name.$n.csv

done
rm -rf $csv_dir/csv.$n/*
echo "鏈€鍚庡悎骞舵垚鐨凜SV鏂囦欢鏄細$csv_dir/$table_name.$n.csv."
done
