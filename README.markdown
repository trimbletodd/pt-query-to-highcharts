pt-query-digest to json to highcharts
========================
We all have come to know and love pt-query-digest, formerly mk-query-digest.  But have you ever wanted to graph your mysql slow queries over time, sliced into individual bits?  Now, with the power of highcharts, you can.  Huzzah.

The script scp's the mysql slow query log from each of the remote hosts to the localhost, slices the data, exports it a json file.  Then you have a rails view that accesses that file, throwing it into highcharts.

It's terribly inefficient.  But it works.

Implemention
================
Put something like this in the crontab of a server.

     0 8,12,18 * * 1-5 /my/dir/scripts/update_pt_query_data.rb -e production --script-dir /my/dir/scripts --daily >> /tmp/update_pt_query_data.log
     0 9-11 * * 1-5 /my/dir/scripts/update_pt_query_data.rb -e production --script-dir /my/dir/scripts >> /tmp/update_pt_query_data.log
     0 13-17 * * 1-5 /my/dir/scripts/update_pt_query_data.rb -e production --script-dir /my/dir/scripts >> /tmp/update_pt_query_data.log
