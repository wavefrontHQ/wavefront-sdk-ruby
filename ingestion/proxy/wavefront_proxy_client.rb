# Wavefront Proxy Client.

# @author Yogesh Prasad Kurmi (ykurmi@vmware.com).

require_relative 'proxy_connection_handler'
require_relative '../../common/utils'
require_relative '../../../wavefront_ruby_sdk/entities/histogram/histogram_granularity'


# WavefrontProxyClient that sends data directly via TCP.
# User should probably attempt to reconnect when exceptions are thrown from any methods.
class WavefrontProxyClient

  attr_reader :proxy_host, :metrics_port, :distribution_port, :tracing_port, :metrics_proxy_connection_handler,
              :histogram_proxy_connection_handler, :tracing_proxy_connection_handler, :default_source


  # Construct Proxy Client.

  # @param host: Hostname of the Wavefront proxy, 2878 by default
  # @param metrics_port:
  # Metrics Port on which the Wavefront proxy is listening on
  # @param distribution_port:
  # Distribution Port on which the Wavefront proxy is listening on
  # @param tracing_port:
  # Tracing Port on which the Wavefront proxy is listening on
  def initialize(host, metrics_port, distribution_port, tracing_port)
    @proxy_host = host
    @metrics_port = metrics_port
    @distribution_port = distribution_port
    @tracing_port = tracing_port
    @metrics_proxy_connection_handler =  metrics_port.nil? ? nil : ProxyConnectionHandler.new(host, metrics_port)
    @histogram_proxy_connection_handler = distribution_port.nil? ? nil : ProxyConnectionHandler.new(host, distribution_port)
    @tracing_proxy_connection_handler = tracing_port.nil? ? nil : ProxyConnectionHandler.new(host, tracing_port)
    @default_source = Socket.gethostname
  end

  # Close all proxy connections.
  def close
    metrics_proxy_connection_handler.close() if metrics_proxy_connection_handler
    histogram_proxy_connection_handler.close() if histogram_proxy_connection_handler
    tracing_proxy_connection_handler.close() if tracing_proxy_connection_handler
  end

  # Get Total Failure Count for all connections.

  # @return: Failure Count
  def failure_count
    failure_count = 0
    failure_count += metrics_proxy_connection_handler.failure_count if metrics_proxy_connection_handler
    failure_count += histogram_proxy_connection_handler.failure_count if histogram_proxy_connection_handler
    failure_count += tracing_proxy_connection_handler.failure_count if tracing_proxy_connection_handler
    failure_count
  end

  # Send Metric Data via proxy.

  # Wavefront Metrics Data format
  # <metricName> <metricValue> [<timestamp>] source=<source> [pointTags]
  # Example: 'new-york.power.usage 42422 1533531013 source=localhost
  #          datacenter=dc1'

  # @param name: Metric Name
  # @type name: str
  # @param value: Metric Value
  # @type value: float
  # @param timestamp: Timestamp
  # @type timestamp: long
  # @param source: Source
  # @type source: str
  # @param tags: Tags
  # @type tags: dict
  def send_metric(name, value, timestamp, source, tags)
    begin
      line_data = WavefrontUtil.metric_to_line_data(name, value, timestamp, source, tags, default_source)
      metrics_proxy_connection_handler.send_data(line_data)
    rescue Exception => error
      metrics_proxy_connection_handler.increment_failure_count
      raise error
    end
  end

  # Send a list of metrics immediately.

  # Have to construct the data manually by calling
  # common.utils.metric_to_line_data()
  # @param metrics: List of string spans data
  # @type metrics: list[str]
  def send_metric_now(metrics)
    metrics.each do |metric|
      begin
        metrics_proxy_connection_handler.send_data(metric)
      rescue Exception => error
        metrics_proxy_connection_handler.increment_failure_count()
        raise error
      end
    end
  end

  # Send Distribution Data via proxy.

  #  Wavefront Histogram Data format
  #  {!M | !H | !D} [<timestamp>] #<count> <mean> [centroids]
  #  <histogramName> source=<source> [pointTags]
  #  Example: '!M 1533531013 #20 30.0 #10 5.1 request.latency
  #            source=appServer1 region=us-west'

  # @param name: Histogram Name
  # @type name: str
  # @param centroids: List of centroids(pairs)
  # @type centroids: list
  # @param histogram_granularities: Histogram Granularities
  # @type histogram_granularities: set
  # @param timestamp: Timestamp
  # @type timestamp: long
  # @param source: Source
  # @type source: str
  # @param tags: Tags
  # @type tags: dict
  def send_distribution(name, centroids, histogram_granularities, timestamp, source, tags)
    begin
      line_data = WavefrontUtil.histogram_to_line_data(name, centroids, histogram_granularities, timestamp, source, tags, default_source)
      histogram_proxy_connection_handler.send_data(line_data)
    rescue Exception => error
      histogram_proxy_connection_handler.increment_failure_count()
      raise error
    end
  end

  # Send a list of distributions immediately.

  # Have to construct the data manually by calling
  # common.utils.histogram_to_line_data()

  # @param distributions: List of string distribution data
  # @type distributions: list[str]
  def send_distribution_now(distributions)
    distributions.each do |distribution|
      begin
        histogram_proxy_connection_handler.send_data(distribution)
      rescue Exception => error
        histogram_proxy_connection_handler.increment_failure_count()
        raise error
      end
    end
  end

  # Send span data via proxy.

  # Wavefront Tracing Span Data format
  #      <tracingSpanName> source=<source> [pointTags] <start_millis>
  #      <duration_milli_seconds>
  #      Example: "getAllUsers source=localhost
  # traceId=7b3bf470-9456-11e8-9eb6-529269fb1459
  # spanId=0313bafe-9457-11e8-9eb6-529269fb1459
  # parent=2f64e538-9457-11e8-9eb6-529269fb1459
  # application=Wavefront http.method=GET
  # 1533531013 343500"

  # @param name: Span Name
  # @type name: str
  # @param start_millis: Start time
  # @type start_millis: long
  # @param duration_millis: Duration time
  # @type duration_millis: long
  # @param source: Source
  # @type source: str
  # @param trace_id: Trace ID
  # @type trace_id: UUID
  # @param span_id: Span ID
  # @type span_id: UUID
  # @param parents: Parents Span ID
  # @type parents: List of UUID
  # @param follows_from: Follows Span ID
  # @type follows_from: List of UUID
  # @param tags: Tags
  # @type tags: list
  # @param span_logs: Span Log
  def send_span(name, start_millis, duration_millis, source, trace_id,
                span_id, parents, follows_from, tags, span_logs)

    begin
      line_data = WavefrontUtil.tracing_span_to_line_data(
              name, start_millis, duration_millis, source, trace_id, span_id,
              parents, follows_from, tags, span_logs, default_source)
      tracing_proxy_connection_handler.send_data(line_data)
    rescue Exception => error
      tracing_proxy_connection_handler.increment_failure_count()
      raise error
    end
  end

  # Send a list of spans immediately.

  # Have to construct the data manually by calling
  # common.utils.tracing_span_to_line_data()

  # @param spans: List of string tracing span data
  # @type spans: list[str]
  def send_span_now(spans)
    spans.each do |span|
      begin
        tracing_proxy_connection_handler.send_data(span)
      rescue Exception => error
        tracing_proxy_connection_handler.increment_failure_count()
        raise error
      end
    end
  end
end