# Script for ad-hoc experiments

# @author Yogesh Prasad Kurmi (ykurmi@vmware.com).

require 'securerandom'

require_relative '../../wavefront-sdk-ruby/wavefront_ruby_sdk/ingestion/proxy/wavefront_proxy_client'


# Wavefront Metrics Data format
# <metricName> <metricValue> [<timestamp>] source=<source> [pointTags]
#
# Example: "new-york.power.usage 42422 1533529977 source=localhost datacenter=dc1"
def send_metrics_via_proxy(proxy_client)
  proxy_client.send_metric(
      "new-york.power.usage", 42422.0, nil, "localhost", {"datacenter"=>"dc1"})

  puts "Sent metric: 'new-york.power.usage' to proxy"
end

# Wavefront Histogram Data format
# {!M | !H | !D} [<timestamp>] #<count> <mean> [centroids] <histogramName> source=<source>
#   [pointTags]

# Example: "!M 1533529977 #20 30.0 #10 5.1 request.latency source=appServer1 region=us-west"
def send_histogram_via_proxy(proxy_client)
  proxy_client.send_distribution(
      "request.latency",
      [[30, 20], [5.1, 10]], Set.new([DAY, HOUR, MINUTE]), nil, "appServer1", {"region"=>"us-west"})

  puts "Sent histogram: 'request.latency' to proxy"
end

# Wavefront Tracing Span Data format
# <tracingSpanName> source=<source> [pointTags] <start_millis> <duration_milli_seconds>

# Example: "getAllUsers source=localhost
#           traceId=7b3bf470-9456-11e8-9eb6-529269fb1459
#           spanId=0313bafe-9457-11e8-9eb6-529269fb1459
#           parent=2f64e538-9457-11e8-9eb6-529269fb1459
#           application=Wavefront http.method=GET
#           1533529977 343500"

def send_tracing_span_via_proxy(proxy_client)
  proxy_client.send_span(
      "getAllProxyUsers", Time.now.to_i, 343500, "localhost",
      SecureRandom.uuid, SecureRandom.uuid, [SecureRandom.uuid], nil,
      {"application"=>"WavefrontRuby", "http.method"=>"GET", "service"=>"TestRuby"}, nil)

  puts "Sent tracing span: 'getAllUsers' to proxy"
end

if __FILE__ == $0
  wavefront_server = ARGV[0]
  token = ARGV[1]
  proxy_host =  ARGV[2] ? ARGV[2] : nil
  metrics_port = ARGV[3] ? ARGV[3] : nil
  distribution_port = ARGV[4] ? ARGV[4] : nil
  tracing_port = ARGV[5] ? ARGV[5] : nil

  wavefront_proxy_client = WavefrontProxyClient.new(proxy_host, metrics_port, distribution_port, tracing_port)

  begin
    while true do
      send_metrics_via_proxy(wavefront_proxy_client)
      #send_histogram_via_proxy(wavefront_proxy_client)
      #send_tracing_span_via_proxy(wavefront_proxy_client)
      sleep 1
    end
  ensure
    wavefront_proxy_client.close
  end
end
