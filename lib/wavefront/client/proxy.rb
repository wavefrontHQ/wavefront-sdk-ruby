# frozen_string_literal: true

# Wavefront Proxy Client.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)

require_relative 'common/proxy_connection_handler'
require_relative 'common/utils'
require_relative 'entities/metrics/wavefront_metric_sender'
require_relative 'entities/histogram/wavefront_histogram_sender'
require_relative 'entities/tracing/wavefront_tracing_span_sender'

require_relative 'internal-metrics/registry'
require_relative 'internal-metrics/reporter'

# Proxy that sends data directly via TCP.
# User should probably attempt to reconnect when exceptions are thrown from
# any methods.
module Wavefront
  class WavefrontProxyClient
    include WavefrontMetricSender
    include WavefrontHistogramSender
    include WavefrontTracingSpanSender

    attr_reader :default_source

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
      @internal_store = InternalMetricsRegistry.new(SDK_METRIC_PREFIX_PROXY, PROCESS_TAG_KEY => (Process.pid||"unknown"))
      @default_source = Socket.gethostname

      # internal metrics
      @points_discarded = @internal_store.counter('points.discarded')
      @points_valid = @internal_store.counter('points.valid')
      @points_invalid = @internal_store.counter('points.invalid')
      @points_dropped = @internal_store.counter('points.dropped')

      @histograms_discarded = @internal_store.counter('histograms.discarded')
      @histograms_valid = @internal_store.counter('histograms.valid')
      @histograms_invalid = @internal_store.counter('histograms.invalid')
      @histograms_dropped = @internal_store.counter('histograms.dropped')

      @spans_discarded = @internal_store.counter('spans.discarded')
      @spans_valid = @internal_store.counter('spans.valid')
      @spans_invalid = @internal_store.counter('spans.invalid')
      @spans_dropped = @internal_store.counter('spans.dropped')

      @metrics_proxy_connection_handler = ProxyConnectionHandler.new(host, metrics_port, @internal_store) unless metrics_port.nil?
      @histogram_proxy_connection_handler = ProxyConnectionHandler.new(host, distribution_port, @internal_store) unless distribution_port.nil?
      @tracing_proxy_connection_handler = ProxyConnectionHandler.new(host, tracing_port, @internal_store) unless tracing_port.nil?

      begin
        @internal_reporter = InternalReporter.new(self, @internal_store)
      rescue StandardError => e
        Wavefront.logger.warn "Failed to create internal metric reporter: #{e.message}"
        # don't re-raise since non-essential
      end
    end

    # Close all proxy connections.
    def close
      @internal_reporter&.stop
      @metrics_proxy_connection_handler&.close
      @histogram_proxy_connection_handler&.close
      @tracing_proxy_connection_handler&.close
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
      if @metrics_proxy_connection_handler.nil?
        @points_discarded.inc
        Wavefront.logger.warn("Can't send data to Wavefront. Please configure metrics port for Wavefront proxy")
        return
      end

      begin
        line_data = WavefrontUtil.metric_to_line_data(name, value, timestamp, source,
                                                      tags, @default_source)
        @points_valid.inc
      rescue StandardError => e
        @points_invalid
        raise e
      end

      begin
        @metrics_proxy_connection_handler.send_data(line_data)
      rescue StandardError => e
        @points_dropped.inc
        raise e
      end
    end

    # Send a list of metrics immediately.
    #
    # Have to construct the data manually by calling
    # common.utils.metric_to_line_data()
    # @param metrics [List<String>] List of string spans data
    def send_metric_now(metrics)
      if @metrics_proxy_connection_handler.nil?
        @points_discarded.inc(metrics.size)
        Wavefront.logger.warn("Can't send data to Wavefront. Please configure metrics port for Wavefront proxy")
        return
      end
      if metrics.nil? || metrics.empty?
        @points_invalid.inc
        raise(ArgumentError, 'point must be non-null and in WF data format')
      end

      metrics.each do |metric|
        begin
          @metrics_proxy_connection_handler.send_data(metric)
        rescue StandardError => e
          @points_dropped.inc
          raise e
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
      if @histogram_proxy_connection_handler.nil?
        @histograms_discarded.inc
        Wavefront.logger.warn("Can't send data to Wavefront. Please configure histogram distribution port for Wavefront proxy")
        return
      end

      begin
        line_data = WavefrontUtil.histogram_to_line_data(name, centroids, histogram_granularities,
                                                         timestamp, source, tags, @default_source)
        @histograms_valid.inc
      rescue StandardError => e
        @histograms_invalid
        raise e
      end

      begin
        @histogram_proxy_connection_handler.send_data(line_data)
      rescue StandardError => e
        @histograms_dropped.inc
        raise e
      end
    end

    # Send a list of distributions immediately.
    #
    # Have to construct the data manually by calling
    # common.utils.histogram_to_line_data()
    #
    # @param distributions [List<String>] List of string distribution data
    def send_distribution_now(distributions)
      if @histogram_proxy_connection_handler.nil?
        @histograms_discarded.inc(distributions.size)
        Wavefront.logger.warn("Can't send data to Wavefront. Please configure histogram distribution port for Wavefront proxy")
        return
      end

      if distributions.nil? || distributions.empty?
        @histograms_invalid.inc
        raise(ArgumentError, 'histogram distribution must be non-null and in WF data format')
      end

      distributions.each do |distribution|
        begin
          @histogram_proxy_connection_handler.send_data(distribution)
        rescue StandardError => e
          @histograms_dropped.inc
          raise e
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
      if @tracing_proxy_connection_handler.nil?
        @spans_discarded.inc
        Wavefront.logger.warn("Can't send data to Wavefront. Please configure tracing port for Wavefront proxy")
        return
      end
      begin
        line_data = WavefrontUtil.tracing_span_to_line_data(
          name, start_millis, duration_millis, source, trace_id, span_id,
          parents, follows_from, tags, span_logs, @default_source
        )
        @spans_valid.inc
      rescue StandardError => e
        @spans_invalid
        raise e
      end

      begin
        @tracing_proxy_connection_handler.send_data(line_data)
      rescue StandardError => e
        @spans_dropped.inc
        raise e
      end
    end

    # Send a list of spans immediately.
    #
    # Have to construct the data manually by calling
    # common.utils.tracing_span_to_line_data()
    #
    # @param spans [List<String>] List of string tracing span data
    def send_span_now(spans)
      if @tracing_proxy_connection_handler.nil?
        @spans_discarded.inc(spans.size)
        Wavefront.logger.warn("Can't send data to Wavefront. Please configure tracing port for Wavefront proxy")
        return
      end
      if spans.nil? || spans.empty?
        @histograms_invalid.inc
        raise(ArgumentError, 'traces must be non-null and in WF data format')
      end
      spans.each do |span|
        begin
          @tracing_proxy_connection_handler.send_data(span)
        rescue StandardError => e
          @spans_dropped.inc
          raise e
        end
      end
    end
  end
end
