#!/bin/sh

cd /home/repo/dbdumps
today=$(date +%Y-%m-%dT%H:%M:%S.sql)
pg_dump | bzip2 -c > $today.bz2
ls -t|grep 'bz2$'|tail -n +14|xargs rm -f
