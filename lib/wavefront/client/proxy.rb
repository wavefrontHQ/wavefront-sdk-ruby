# Wavefront Proxy Client.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)

require_relative 'common/proxy_connection_handler'
require_relative 'common/utils'
require_relative 'entities/histogram/histogram_granularity'
require_relative 'entities/metrics/wavefront_metric_sender'
require_relative 'entities/histogram/wavefront_histogram_sender'
require_relative 'entities/tracing/wavefront_tracing_span_sender'


# Proxy that sends data directly via TCP.
# User should probably attempt to reconnect when exceptions are thrown from
# any methods.
module Wavefront
  class WavefrontProxyClient
    include WavefrontMetricSender
    include WavefrontHistogramSender
    include WavefrontTracingSpanSender

    # Construct Proxy Client.
    #
    # @param host [String] Hostname of the Wavefront proxy, 2878 by default
    # @param metrics_port [Integer] Metrics Port on which the Wavefront proxy is
    # listening on
    # @param distribution_port [Integer] Distribution Port on which the Wavefront
    # proxy is listening on
    # @param tracing_port [Integer] Tracing Port on which the Wavefront proxy is
    # listening on
    def initialize(host, metrics_port, distribution_port, tracing_port)
      @metrics_proxy_connection_handler =  metrics_port.nil? ? nil : ProxyConnectionHandler.new(host, metrics_port.to_i)
      @histogram_proxy_connection_handler = distribution_port.nil? ? nil : ProxyConnectionHandler.new(host, distribution_port.to_i)
      @tracing_proxy_connection_handler = tracing_port.nil? ? nil : ProxyConnectionHandler.new(host, tracing_port.to_i)
      @default_source = Socket.gethostname
    end

    # Close all proxy connections.
    def close
      @metrics_proxy_connection_handler.close() if @metrics_proxy_connection_handler
      @histogram_proxy_connection_handler.close() if @histogram_proxy_connection_handler
      @tracing_proxy_connection_handler.close() if @tracing_proxy_connection_handler
    end

    # Get Total Failure Count for all connections.
    #
    # @return [Integer] Failure Count
    def failure_count
      failure_count = 0
      failure_count += @metrics_proxy_connection_handler.failure_count if @metrics_proxy_connection_handler
      failure_count += @histogram_proxy_connection_handler.failure_count if @histogram_proxy_connection_handler
      failure_count += @tracing_proxy_connection_handler.failure_count if @tracing_proxy_connection_handler
      failure_count
    end

    # Send Metric Data via proxy.
    #
    # Wavefront Metrics Data format
    #   <metricName> <metricValue> [<timestamp>] source=<source> [pointTags]
    #
    # Example
    #   'new-york.power.usage 42422 1533531013 source=localhost
    #   datacenter=dc1'
    #
    # @param name [String] Metric Name
    # @param value [Float] Metric Value
    # @param timestamp [Long] Timestamp
    # @param source [String] Source
    # @param tags [Hash] Tags
    def send_metric(name, value, timestamp, source, tags)
      begin
        line_data = WavefrontUtil.metric_to_line_data(name, value, timestamp, source,
                                                      tags, @default_source)
        @metrics_proxy_connection_handler.send_data(line_data)
      rescue Exception => error
        @metrics_proxy_connection_handler.increment_failure_count
        raise error
      end
    end

    # Send a list of metrics immediately.
    #
    # Have to construct the data manually by calling
    # common.utils.metric_to_line_data()
    # @param metrics [List<String>] List of string spans data
    def send_metric_now(metrics)
      metrics.each do |metric|
        begin
          @metrics_proxy_connection_handler.send_data(metric)
        rescue Exception => error
          @metrics_proxy_connection_handler.increment_failure_count()
          raise error
        end
      end
    end

    # Send Distribution Data via proxy.
    #
    # Wavefront Histogram Data format
    #  {!M | !H | !D} [<timestamp>] #<count> <mean> [centroids]
    #  <histogramName> source=<source> [pointTags]
    #
    # Example
    #   '!M 1533531013 #20 30.0 #10 5.1 request.latency
    #   source=appServer1 region=us-west'
    #
    # @param name [String] Histogram Name
    # @param centroids [List] List of centroids(pairs)
    # @param histogram_granularities [Set] Histogram Granularities
    # @param timestamp [Long] Timestamp
    # @param source [String] Source
    # @param tags [Hash] Tags
    def send_distribution(name, centroids, histogram_granularities, timestamp,
                          source, tags)
      begin
        line_data = WavefrontUtil.histogram_to_line_data(name, centroids, histogram_granularities,
                                                        timestamp, source, tags, @default_source)
        @histogram_proxy_connection_handler.send_data(line_data)
      rescue Exception => error
        @histogram_proxy_connection_handler.increment_failure_count()
        raise error
      end
    end

    # Send a list of distributions immediately.
    #
    # Have to construct the data manually by calling
    # common.utils.histogram_to_line_data()
    #
    # @param distributions [List<String>] List of string distribution data
    def send_distribution_now(distributions)
      distributions.each do |distribution|
        begin
          @histogram_proxy_connection_handler.send_data(distribution)
        rescue Exception => error
          @histogram_proxy_connection_handler.increment_failure_count()
          raise error
        end
      end
    end

    # Send span data via proxy.
    #
    # Wavefront Tracing Span Data format
    #      <tracingSpanName> source=<source> [pointTags] <start_millis>
    #      <duration_milli_seconds>
    #
    # Example
    #   "getAllUsers source=localhost
    #   traceId=7b3bf470-9456-11e8-9eb6-529269fb1459
    #   spanId=0313bafe-9457-11e8-9eb6-529269fb1459
    #   parent=2f64e538-9457-11e8-9eb6-529269fb1459
    #   application=Wavefront http.method=GET
    #   1533531013 343500"
    #
    # @param name [String] Span Name
    # @param start_millis [Long] Start time
    # @param duration_millis [Long] Duration time
    # @param source [String] Source
    # @param trace_id [UUID] Trace ID
    # @param span_id [UUID] Span ID
    # @param parents [List<UUID>] Parents Span ID
    # @param follows_from [List<UUID>] Follows Span ID
    # @param tags [List] Tags
    # @param span_logs [] Span Log
    def send_span(name, start_millis, duration_millis, source, trace_id,
                  span_id, parents, follows_from, tags, span_logs)
      begin
        line_data = WavefrontUtil.tracing_span_to_line_data(
                name, start_millis, duration_millis, source, trace_id, span_id,
                parents, follows_from, tags, span_logs, @default_source)
        @tracing_proxy_connection_handler.send_data(line_data)
      rescue Exception => error
        @tracing_proxy_connection_handler.increment_failure_count()
        raise error
      end
    end

    # Send a list of spans immediately.
    #
    # Have to construct the data manually by calling
    # common.utils.tracing_span_to_line_data()
    #
    # @param spans [List<String>] List of string tracing span data
    def send_span_now(spans)
      spans.each do |span|
        begin
          @tracing_proxy_connection_handler.send_data(span)
        rescue Exception => error
          @tracing_proxy_connection_handler.increment_failure_count()
          raise error
        end
      end
    end
  end
end