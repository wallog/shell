#!/bin/bash

set -e

sqldir="/home/sqldir"
ftpDIR="/home/ftp/orcl"
Todate=$(date +%Y%m%d-%H%M%S)
csvdir="/home/wanglong/csv"
tablename="DQLLB"

[[ ! -d $sqldir ]] && mkdir -p $sqldir

#get csv first line
for csv in $(ls $csvdir);do
  col1=$(sed -n '1p' $csvdir/$csv | cut -d "," -f 2-)
  col2=$(sed -n '1p' $csvdir/$csv | cut -d "," -f 2- | sed "s#\"\,\"#||\'\",\"\'||#g"| sed "s/^\"/\"\'||/" |sed "s/\"$/||\'\"/")
  tablename=${csv%%.*}
echo "set linesize 500
set pagesize 0
set feedback off
set echo off
set numwidth 20
set newp none
set trispool on
alter session set nls_date_format='yyyy-mm-dd';
spool $ftpDIR/$tablename.csv;
select '"$col1"' from dual;
select '$col2' from $tablename;
spool off
exit" > $sqldir/$tablename.sql
done

