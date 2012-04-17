pt-query-digest to json to highcharts
========================
Ever wanted to graph your mysql slow queries over time, sliced into individual bits?  Now you can, with highcharts.  Huzzah.

The script does an scp of the mysql slow query log from each of the hosts, slices the data, exports it a json file.  Then you have a rails view that accesses that file, throwing it into highcharts.

Implemention
================
Put something like this in the crontab of a server.

0 8,12,18 * * 1-5 /my/dir/scripts/update_pt_query_data.rb -e production --script-dir /my/dir/scripts --daily >> /tmp/update_pt_query_data.log
0 9-11 * * 1-5 /my/dir/scripts/update_pt_query_data.rb -e production --script-dir /my/dir/scripts >> /tmp/update_pt_query_data.log
0 13-17 * * 1-5 /my/dir/scripts/update_pt_query_data.rb -e production --script-dir /my/dir/scripts >> /tmp/update_pt_query_data.log
