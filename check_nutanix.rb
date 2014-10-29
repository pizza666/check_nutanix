#!/usr/bin/ruby
# nagios-nutanix
# 2014-10-29  Andri Steiner <asteiner@snowflake.ch>

# include modules
require 'optparse'
require 'ostruct'
require 'pp'
require 'net/https'
require 'json'

# Option Parser
class Optparse
  def self.parse(args)

    # default Values
    options = OpenStruct.new
    options.verbose = false
    options.host = 'localhost'
    options.port = '9440'
    options.username = 'admin'
    options.password = 'admin'

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options]"

      opts.separator ""
      opts.separator "Specific options:"

      opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
        options.verbose = true
        $verbose = true
      end
      opts.on("--host [Host]", "-H", "your Nutanix Web Console Hostname, defaults to #{$host}") do |host|
        options.host = host
      end
      opts.on("--port [Port]", "-p", Integer, "your Nutanix Web Console Port, defaults to #{$port}") do |port|
        options.port = port
      end
      opts.on("--username [Username]", "-u", "your Nutanix Web Console Username, defaults to #{$username}") do |username|
        options.username = username
      end
      opts.on("--password [Password]", "-p", "your Nutanix Web Console Password, defaults to #{$password}") do |password|
        options.password = password
      end
      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit 0
      end
    end
    opt_parser.parse!(args)
    options
  end
end

# Nutanix API Abstraction
class NutanixAPI

  # Connect to the API
  def initialize
    puts "Connecting to https://#{$options.host}:#{$options.port}" if $verbose
    $http = Net::HTTP.new($options.host, $options.port)
    $http.use_ssl = true
  end

  # get Values
  def get(url)
    puts "GET from #{url}" if $verbose
    req = Net::HTTP::Get.new('/' + url)
    req.basic_auth $options.username, $options.password
    response = $http.request(req)
    if response.code != '200'
      puts "ERROR: API return Value " + response.code
      exit 2
    end
    puts "Response: #{response.body}" if $verbose
    return JSON.load(response.body)
  end
end

# parse Options
$options = Optparse.parse(ARGV)

# initialize API
API = NutanixAPI.new

# initialize return Buffers
returnBuffer = " - "
returnValue = 0

# check VM Health
vmhealth = API.get("PrismGateway/services/rest/v1/vms/health_check_summary")
vmCritical = vmhealth["healthSummary"]["Critical"]
vmUnknown = vmhealth["healthSummary"]["Unknown"]
vmGood = vmhealth["healthSummary"]["Good"]
vmWarning = vmhealth["healthSummary"]["Warning"]
returnBuffer << "VM Summary: #{vmGood} Good, #{vmUnknown} Unknown, #{vmWarning} Warning, #{vmCritical} Critical."
returnValue = 3 if vmUnknown != 0
returnValue = 1 if vmWarning != 0
returnValue = 2 if vmCritical != 0

# check if there are any unresolved/unacknowledged Alerts
alerts = API.get('PrismGateway/services/rest/v1/alerts/?resolved=false&acknowledged=false')
alertCount = alerts['metadata']['totalEntities']
returnBuffer << " #{alertCount} pending Alerts."
returnValue = 2 if alertCount != 0

# prepend Status Message
case returnValue
  when 0
    returnBuffer.prepend("OK")
  when 1
    returnBuffer.prepend("WARNING")
  when 2
    returnBuffer.prepend("CRITICAL")
  when 3
    returnBuffer.prepend("UNKNOWN")
end

puts returnBuffer
exit returnValue


