#!/usr/bin/ruby
# nagios-nutanix
# 2014-10-29  Andri Steiner <asteiner@snowflake.ch>
# v2 by Jan-Dirk Lehde <jan-dirk.lehde@nassmagnet.de

# include modules
require 'optparse'
require 'ostruct'
require 'pp'
require 'net/https'
require 'openssl'
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
    options.certificate = '/etc/icinga/icinga.pem'

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
      opts.on("--certificate","-c","a client certificate to authenticate with Nutanix Web Console") do |certificate|
        option.certificate = certificate
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
    @cert_raw = File.read($options.certificate)
    @cert_key_raw = @cert_raw
    $https = Net::HTTP.new($options.host, $options.port)
    $https.use_ssl = true
    $https.cert = OpenSSL::X509::Certificate.new(@cert_raw)
    $https.key = OpenSSL::PKey::RSA.new(@cert_key_raw)
    $https.verify_mode = OpenSSL::SSL::VERIFY_PEER
  end

  # get Values
  def get(url)
    puts "GET from #{url}" if $verbose
    req = Net::HTTP::Get.new('/' + url)
    # req.basic_auth $options.username, $options.password
    response = $https.request(req)
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

# initialize return Buffersi and counters
returnValue = 0
returnBuffer = ""

counterUnknown = 0
counterWarn = 0
counterCrit = 0

# check if there are any unresolved/unacknowledged Alerts
alerts = API.get('PrismGateway/services/rest/v1/alerts/?resolved=false&acknowledged=false')

counterWarn = 0
counterCrit = 0

# lets check all entities and its severity 
# and display every single open alert

alerts["entities"].each do |alert|
  
  # fill contextTypes with Values in alertTitle
  alertTitle = alert["alertTitle"]
  alert["contextTypes"].each.with_index(0) do |contextType, index|
    alertTitle = alertTitle.gsub('{' + contextType + '}',alert["contextValues"][index])  
  end

  returnBuffer << alert["severity"][1..-1].upcase + " - " + alertTitle + "\n"
  case alert["severity"]
    when "kWarning"
      counterWarn +=1
    when "kCritical"
      counterCrit +=1
  end    
end

# check VM Health
vmhealth = API.get("PrismGateway/services/rest/v1/vms/health_check_summary")

vmCritical = vmhealth["healthSummary"]["Critical"]
counterCrit += vmCritical

vmUnknown = vmhealth["healthSummary"]["Unknown"]
counterUnknown += vmUnknown

vmGood = vmhealth["healthSummary"]["Good"]

vmWarning = vmhealth["healthSummary"]["Warning"]
counterWarn += vmWarning

vmSeverity = "OK"
vmSeverity = "UNKNOWN" if vmUnknown > 0
vmSeverity = "WARNING" if vmWarning > 0
vmSeverity = "CRITICAL" if vmCritical > 0

returnBuffer = vmSeverity + " - VM Summary: #{vmGood} Good, #{vmUnknown} Unknown, #{vmWarning} Warning, #{vmCritical} Critical.\n"

# analyse counter and set returnValue
returnValue = 3 if counterUnknown > 0
returnValue = 1 if counterWarn > 0
returnValue = 2 if counterCrit > 0

puts returnBuffer
exit returnValue


