#!/usr/bin/env ruby
DEBUG = 1

#-------------------------------------------------------
# FUNCTION: get_pt-query-digest_interval_query
#     DESC: runs pt-query-digest with args
#     ARGS: since - time to start (--since)
#           until - time to stop (--until)
#           file - mysqld_slow.log
#
#   RETURN: results hash
#-------------------------------------------------------
def get_pt_query_digest_interval_query(args)
  raise Exception.new("Must define since,until,file in args.") if args[:since].nil? || args[:until].nil? || args[:file].nil?
  res = {}
  pt_res = `pt-query-digest --since "#{args[:since].to_formatted_s(:db)}" --until "#{args[:until].to_formatted_s(:db)}" --report-format profile --limit 20 #{args[:file]}`.split("\n")

  pt_res.shift(4)
  pt_res.map{|l| l.split}.each do |pt_line|
    row = {
      :fingerprint => pt_line[2],
      :response_time => pt_line[3].to_i,
      :response_pct => pt_line[4].to_f
    } unless pt_line[2] =~ /MISC/
    res[pt_line[2]] = row
  end
  res
end

#-------------------------------------------------------
# FUNCTION: build_pt_query-digest_array
#     ARGS: since - time to start (--since)
#           until - time to stop (--until)
#           interval - time interval for each row
#           file - mysqld_slow.log
#
#   RETURN: array of hashes
#-------------------------------------------------------
def build_pt_query_digest_array(args)
  raise Exception.new("Must define since,until,interval,file in args.") if args[:since].nil? || args[:until].nil? || args[:file].nil? || args[:interval].nil?
  res=[]
  interval = 0
  while (args[:since] + args[:interval]*(interval+1)) <= args[:until] do
    puts "Building: #{args[:since]+(interval*args[:interval])}"
    res[interval]=get_pt_query_digest_interval_query({:since => args[:since]+(args[:interval]*interval),
                                                       :until => args[:since]+(args[:interval]*(interval+1)),
                                                       :file => args[:file]})
    interval += 1
  end
  res
end

#-------------------------------------------------------
# FUNCTION: convert_pt_query_to_series
#     ARGS: pt_query_array
#
#   RETURN: array of series
#-------------------------------------------------------
def convert_pt_query_to_series(pt_query)
  num_series=pt_query.count
  fingerprints=Set.new
  
  # Get list of fingerprints
  pt_query.each do |row|
    row.each {|k,v| fingerprints.add(k)}
  end

  fingerprints.delete(nil)

  series={}
  # cycle through list
  fingerprints.each do |f|
    series[f]=[]
    (0...num_series).each do |i|
      val = pt_query[i][f]
      series[f].push(val)
    end
  end
  series
end

#-------------------------------------------------------
# FUNCTION: get_pt_series_by_key
#-------------------------------------------------------
def get_pt_series_by_key(args)
  raise Exception.new("Poorly defined args.") if args[:key].nil? || args[:pt_query_series].nil?
  pt=args[:pt_query_series]
  key=args[:key]
  
  res=[]
  pt.each do |vals|
    if vals
      res.push(vals[key])
    else
      res.push(0)
    end
  end
  res
end

#-------------------------------------------------------
# FUNCTION: get_all_pt_series_by_key
#-------------------------------------------------------
def get_all_pt_series_by_key(args)
  raise Exception.new("Poorly defined args.") if args[:key].nil? || args[:pt_query_series].nil?
  pt_series=args[:pt_query_series]
  key=args[:key]

  res={}
  pt_series.each do |k,v|
    res[k]=get_pt_series_by_key({:pt_query_series => v, :key => key})
  end
  res.reject{|k,v| v.sum<args[:min_value]}
end  

#-------------------------------------------------------
# FUNCTION: get_query_text_to_pt_query
#-------------------------------------------------------
def get_query_text_to_pt_query(args)
  raise Exception.new("Must define since,until,pt_query_series,file in args.") if args[:since].nil? || args[:until].nil? || args[:file].nil? || args[:query_checksums].nil?
  res={}
  i=0;
  tot=args[:query_checksums].count
  args[:query_checksums].each do |k|
    puts "#{i+=1} of #{tot}"
    res[k]=`pt-query-digest #{args[:file]} --since "#{args[:since].strftime("%Y-%m-%d %H:%M:%S")}" --until "#{args[:until].strftime("%Y-%m-%d %H:%M:%S")}"  --filter 'make_checksum($event->{fingerprint}) eq "#{k.last(-2)}"' --report-format query_report | grep -v \\\#`
  end
  res
end

#-------------------------------------------------------
# FUNCTION: pt_query_to_json
#-------------------------------------------------------
def pt_query_to_json(pt_series, query_texts)
  res=[]
  pt_series.each do |k,v|
    res.push({"name" => "#{k} | #{query_texts[k].slice(0,100)}", "data" => v})
  end
  "#{res.to_json};\n"
end

#-------------------------------------------------------
# FUNCTION: js_time
# js wants a zero-based array for month, so give
#-------------------------------------------------------
def js_time(t)
  # (t-1.month).getgm.strftime("%Y, %m, %d, %H, %M, %S")
  (t-1.month).strftime("%Y, %m, %d, %H, %M, %S")
end

#-------------------------------------------------------
# FUNCTION: get_plot_options
#-------------------------------------------------------
def get_plot_options(args)
  raise Exception.new("Poorly defined args.") if args[:since].nil? || args[:until].nil? || args[:interval].nil? || args[:host].nil?
str = <<NACHOS
var plot_options_#{args[:host]} = { 
          series: {
            cursor: 'pointer',
            pointStart:  Date.UTC(#{js_time(args[:since] + (args[:interval]/2))}),
            pointInterval: #{args[:interval]*1000},
            point: {
              events: {
                click: function() {
                  hs.htmlExpand(null, {
                    pageOrigin: {
                      x: this.pageX,
                      y: this.pageY
                    },
                    headingText: this.series.name.slice(0,19),
                    maincontentText: 
                      Highcharts.dateFormat('%Y-%m-%d %H:%M:%S (%a)', this.x) +':<br/> ' +
                      'Response time: ' + this.y +'<BR>'+
                      this.series.name,
                    width: 200
                  });
                }
              }
            },
            marker: {
              lineWidth: 1
            }
          }

 };
var subtitle_text_#{args[:host]} = "From #{args[:since]} to #{args[:until]} in intervals of #{args[:interval]}";
NACHOS
end
  

#-------------------------------------------------------
# FUNCTION: main
#-------------------------------------------------------

require 'rubygems'
require 'optparse'
require 'activesupport'
require 'pp'
require 'set'

current_time = Time.now
input_file_name = '/var/log/mysql/mysqld-slow.log'
output_prefix='pt_query_data'
since_time = 1.day.ago
until_time = Time.now
interval = 3600
key = :response_time
min_value=10
file = "#{output_prefix}_#{Time.now.strftime("%Y%m%d")}.js"
host = "localhost"

ARGV.options do |o|
  script_name = File.basename($0)

  o.set_summary_indent('  ')
  o.banner = "Usage: #{script_name} [options]"
  o.define_head "  Parse mysql slow query logs with pt-query-digest and print pretty data. "
  o.separator ""
  o.on("--input-file [file]", String, "filename to parse") { |input_file_name| }
  o.on("--output-file [file]", String, "filename to write") { |output_file| file = output_file }
  o.on("--filter [min_value]", Integer, "min value") { |min_value| }
  o.on("--key [key]", String, "key to extract") { |key| key = key.to_sym}
  o.on("--host [host]", String, "host of db") { |h| host = h}
  o.on("--interval [incr]", Integer, "parsing interval in minutes") { |interval| }
  o.on("--since [since_time]", String, "start time") { |since_time| since_time = since_time.to_time(:local) }
  o.on("--since_ruby [since_time]", String, "start time in ruby execution string") { |str| since_time = eval(str) }
  o.on("--until [until_time]", String, "stop time") { |until_time| until_time = until_time.to_time(:local)}
  o.on_tail("-h", "--help", "Show this help message.") { puts o; exit }
  o.parse!
end

puts "Building pt_query_digest intervals from #{since_time} to #{until_time} in intervals of #{interval} seconds for #{host}."

pt_digest_results = build_pt_query_digest_array({:since => since_time,
                                                  :until => until_time,
                                                  :interval => interval,
                                                  :file => input_file_name})
pt_series_results = convert_pt_query_to_series(pt_digest_results)

response_times = get_all_pt_series_by_key({:pt_query_series => pt_series_results, :key => :response_time, :min_value=> min_value})

puts "Getting SQL text for queries"
query_texts = get_query_text_to_pt_query({:since => since_time,
                                           :until => until_time,
                                           :interval => interval,
                                           :file => input_file_name,
                                           :query_checksums=>response_times.keys})

response_times_json = "var series_data_#{host} = " + pt_query_to_json(response_times, query_texts)

File.open(file, 'w') do |f|
  f.write(response_times_json)
  f.write(get_plot_options({:since => since_time,
                             :until => until_time,
                             :host => host,
                             :interval => interval}))
end

