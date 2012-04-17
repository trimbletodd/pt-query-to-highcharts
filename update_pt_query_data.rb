#!/usr/bin/env ruby

require 'optparse'

env = ENV['RAILS_ENV'] || "development"
hosts=["db1", "db1", "db3"]

script_dir = "."
data_dir = nil
process_hourly,process_daily = true,false

ARGV.options do |o|
  script_name = File.basename($0)

  o.set_summary_indent('  ')
  o.banner = "Usage: #{script_name} [options]"
  o.define_head "  Update data from pt-query-digest."
  o.separator ""
  o.on("--script-dir [dir]", String, "directory containing script to parse") { |dir| script_dir=dir }
  o.on("--data-dir [dir]", String, "filename to write") { |dir| data_dir=dir }
  o.on("--daily", "Process daily stats in addition to hourly") { process_daily=true }
  o.on("-e", "--environment [env]", "environment to run") { |e| env=e }
  o.on("--no-hourly", "Process only daily stats") { process_hourly=false }
  o.on("--hosts [hosts]", "comma separated list of hosts") { |h| 
    if h.nil?
      puts o
      exit
    else 
      hosts=h.split(',')
    end }
  o.on_tail("-h", "--help", "Show this help message.") { puts o; exit }
  o.parse!
end

data_dir ||= "/my/data/dir/#{env}/current/public/data_public/misc"

append_path=".mydomain.com"

hosts.each do |host|
  cmd = "scp #{host+append_path}:/var/log/mysql/mysqld-slow.log /tmp/mysqld-slow.log.#{host}"
  system(cmd)

  if process_hourly
    cmd = <<NACHOS
    #{script_dir}/pt_query_digest_to_json.rb \
    --input-file /tmp/mysqld-slow.log.#{host} \
    --since_ruby "3.hours.ago" \
    --interval $((300)) \
    --filter 15 \
    --output-file "#{data_dir}/pt_query_data_3_hours_#{host}.js" \
    --host #{host}
NACHOS
    system(cmd)
  end

  if process_daily
    cmd = <<NACHOS
    #{script_dir}/pt_query_digest_to_json.rb \
    --input-file /tmp/mysqld-slow.log.#{host} \
    --since_ruby "3.days.ago" \
    --interval $((3600)) \
    --filter 200 \
    --output-file "#{data_dir}/pt_query_data_3_days_#{host}.js" \
    --host #{host}
NACHOS
    system(cmd)
  end
end
