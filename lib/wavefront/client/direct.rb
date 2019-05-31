# frozen_string_literal: true

# Wavefront Direct Ingestion Client.
# Sends data directly to Wavefront cluster via the direct ingestion API.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)

require 'uri'
require 'socket'
require 'net/http'

require_relative 'common/utils'
require_relative 'entities/metrics/wavefront_metric_sender'
require_relative 'entities/histogram/wavefront_histogram_sender'
require_relative 'entities/tracing/wavefront_tracing_span_sender'
require_relative 'common/constants'

require_relative 'internal-metrics/registry'
require_relative 'internal-metrics/reporter'

module Wavefront
  class WavefrontDirectIngestionClient
    include WavefrontMetricSender
    include WavefrontHistogramSender
    include WavefrontTracingSpanSender

    attr_reader :default_source

    # Construct Direct Client.
    #
    # @param server [String] Server address, Example: https://INSTANCE.wavefront.com
    # @param token [String] Token with Direct Data Ingestion permission granted
    # @param max_queue_size [Integer] Max Queue Size, size of internal data buffer
    # for each data type, 50000 by default.
    # @param batch_size [Integer] Batch Size, amount of data sent by one api call,
    # 10000 by default
    # @param flush_interval_seconds [Integer] Interval flush time, 5 secs by default
    def initialize(server, token, max_queue_size: 50_000, batch_size: 10_000, flush_interval_seconds: 5)
      @server = server
      @default_source = Socket.gethostname || 'wavefrontDirectSender'

      @batch_size = batch_size
      @metrics_buffer = SizedQueue.new(max_queue_size)
      @histograms_buffer = SizedQueue.new(max_queue_size)
      @tracing_spans_buffer = SizedQueue.new(max_queue_size)
      @headers = { 'Content-Type' => 'application/octet-stream',
                   'Content-Encoding' => 'gzip',
                   'Authorization' => 'Bearer ' + token }.freeze

      @lock = Mutex.new
      @closed = false

      @internal_store = InternalMetricsRegistry.new(SDK_METRIC_PREFIX_DIRECT, PROCESS_TAG_KEY => (Process.pid || 'unknown'))

      # gauges
      @internal_store.gauge('points.queue.size') { @metrics_buffer.size }
      @internal_store.gauge('points.queue.remaining_capacity') { @metrics_buffer.max - @metrics_buffer.size }
      @internal_store.gauge('histograms.queue.size') { @histograms_buffer.size }
      @internal_store.gauge('histograms.queue.remaining_capacity') { @histograms_buffer.max - @histograms_buffer.size }
      @internal_store.gauge('spans.queue.size') { @tracing_spans_buffer.size }
      @internal_store.gauge('spans.queue.remaining_capacity') { @tracing_spans_buffer.max - @tracing_spans_buffer.size }

      # counters
      @points_valid = @internal_store.counter('points.valid')
      @points_invalid = @internal_store.counter('points.invalid')
      @points_dropped = @internal_store.counter('points.dropped')
      @point_report_errors = @internal_store.counter('points.report.errors')

      @histograms_valid = @internal_store.counter('histograms.valid')
      @histograms_invalid = @internal_store.counter('histograms.invalid')
      @histograms_dropped = @internal_store.counter('histograms.dropped')
      @histogram_report_errors = @internal_store.counter('histograms.report.errors')

      @spans_valid = @internal_store.counter('spans.valid')
      @spans_invalid = @internal_store.counter('spans.invalid')
      @spans_dropped = @internal_store.counter('spans.dropped')
      @span_report_errors = @internal_store.counter('spans.report.errors')

      @flush_interval_seconds = flush_interval_seconds
      @timer = EarlyTickTimer.new(@flush_interval_seconds, false) { flush_now }

      # Start internal metrics
      @internal_reporter = InternalReporter.new(self, @internal_store)
    end

    # Get Total Failure Count
    def failure_count
      @point_report_errors.value + @histogram_report_errors.value + @span_report_errors.value
    end

    # Flush all buffer before close the client.
    def close(timeout = 5)
      @timer.stop(timeout)
      flush_now
      @internal_reporter.stop
    end

    # Flush all the data buffer immediately.
    def flush_now
      internal_flush(@metrics_buffer, WAVEFRONT_METRIC_FORMAT, 'points', @point_report_errors)
      internal_flush(@histograms_buffer, WAVEFRONT_HISTOGRAM_FORMAT, 'histograms', @histogram_report_errors)
      internal_flush(@tracing_spans_buffer, WAVEFRONT_TRACING_SPAN_FORMAT, 'spans', @span_report_errors)
    end

    # Get all data from one data buffer to a list, and report that list.
    #
    # @param data_buffer [Queue] Data buffer to be flush and sent
    # @param data_format [String] Type of data to be sent
    def internal_flush(data_buffer, data_format, entity_prefix, report_errors)
      data = []
      data << data_buffer.pop until data_buffer.empty?
      batch_report(data, data_format, entity_prefix, report_errors) unless data.empty?
    end

    # One api call sending one given string data.

    # @param points [List<String>] List of data in string format, concat by '\n'
    # @param data_format [String] Type of data to be sent
    def report(points, data_format)
      payload = WavefrontUtil.gzip_compress(points)
      uri = URI.parse(@server)
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = true
      request = Net::HTTP::Post.new('/report?f=' + data_format, @headers)
      request.body = payload

      response = https.request(request)
      unless [200, 202].include? response.code.to_i
        Wavefront.logger.warn "Dropped points, Response #{response.code} #{response.message}"
      end
      response.code.to_i
    end

    # One api call sending one given list of data.
    #
    # @param batch_line_data [List] List of data to be sent
    # @param data_format [String] Type of data to be sent
    def batch_report(batch_line_data, data_format, entity_prefix, report_errors)
      # Split data into chunks, each with the size of given batch_size
      data_chunks = WavefrontUtil.chunks(batch_line_data, @batch_size)
      data_chunks.each do |batch|
        begin
          # report once per batch
          status_code = report(batch.join + "\n", data_format)
          @internal_store.counter("#{entity_prefix}.report.#{status_code}").inc
          unless [200, 202].include? status_code.to_i
            @internal_store.counter("#{entity_prefix}.dropped").inc(batch.size)
          end
        rescue StandardError => e
          report_errors.inc
          Wavefront.logger.error "Failed to report #{data_format} data points to wavefront. Error: #{e}"
        end
      end
    end

    # Send Metric Data via direct ingestion API.
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
        line_data = WavefrontUtil.metric_to_line_data(name, value, timestamp, source, tags, @default_source)
        @points_valid.inc
      rescue StandardError => e
        @points_invalid
        raise e
      end
      begin
        @metrics_buffer.push(line_data, non_block = true)
      rescue StandardError => e
        @points_dropped.inc
        Wavefront.logger.warn('Buffer full, dropping metric point: ' + line_data)
      end
    end

    # Send a list of metrics immediately.
    #
    # Have to construct the data manually by calling
    # common.utils.metric_to_line_data()
    # @param metrics [List<String>] List of string spans data
    def send_metric_now(metrics)
      if metrics.nil? || metrics.empty?
        @points_invalid.inc
        raise(ArgumentError, 'point must be non-null and in WF data format')
      end
      @points_valid.inc(metrics.size)
      batch_report(metrics, WAVEFRONT_METRIC_FORMAT)
    end

    # Send Distribution Data via proxy.
    #
    # Wavefront Histogram Data format
    #   {!M | !H | !D} [<timestamp>] #<count> <mean> [centroids]
    #   <histogramName> source=<source> [pointTags]
    #
    # Example
    #   "!M 1533531013 #20 30.0 #10 5.1 request.latency
    #   source=appServer1 region=us-west"
    #
    # @param name [String] Histogram Name
    # @param centroids [List] List of centroids(pairs)
    # @param histogram_granularities [Set] Histogram Granularities
    # @param timestamp [Long] Timestamp
    # @param source [String] Source
    # @param tags [Hash]
    def send_distribution(name, centroids, histogram_granularities,
                          timestamp, source, tags)
      begin
        line_data = WavefrontUtil.histogram_to_line_data(name, centroids, histogram_granularities,
                                                         timestamp, source, tags, @default_source)
        @histograms_valid.inc
      rescue StandardError => e
        @histograms_invalid.inc
        raise e
      end

      begin
        @histograms_buffer.push(line_data, non_block = true)
      rescue StandardError => e
        @histograms_dropped.inc
        Wavefront.logger.warn('Buffer full, dropping histograms: ' + line_data)
      end
    end

    # Send a list of distribution immediately.
    #
    # Have to construct the data manually by calling
    # common.utils.histogram_to_line_data()
    #
    # @param distributions [List<String>] List of string spans data
    def send_distribution_now(distributions)
      if distributions.nil? || distributions.empty?
        @histograms_invalid.inc
        raise(ArgumentError, 'Distributions must be non-null and in WF data format')
      end
      @points_valid.inc(distributions.size)
      batch_report(distributions, WAVEFRONT_HISTOGRAM_FORMAT)
    end

    # Send span data via proxy.
    #
    # Wavefront Tracing Span Data format
    #   <tracingSpanName> source=<source> [pointTags] <start_millis>
    #   <duration_milli_seconds>
    #
    # Example:
    #   "getAllUsers source=localhost
    #    traceId=7b3bf470-9456-11e8-9eb6-529269fb1459
    #    spanId=0313bafe-9457-11e8-9eb6-529269fb1459
    #    parent=2f64e538-9457-11e8-9eb6-529269fb1459
    #    application=Wavefront http.method=GET
    #    1533531013 343500"
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
    # @param span_logs  Span Log
    def send_span(name, start_millis, duration_millis, source, trace_id,
                  span_id, parents, follows_from, tags, span_logs)

      begin
        line_data = WavefrontUtil.tracing_span_to_line_data(name, start_millis, duration_millis,
                                                            source, trace_id, span_id, parents,
                                                            follows_from, tags, span_logs, @default_source)
        @spans_valid.inc
      rescue StandardError => e
        @spans_invalid.inc
        raise e
      end

      begin
        @tracing_spans_buffer.push(line_data, non_block = true)
      rescue StandardError => e
        @spans_dropped.inc
        Wavefront.logger.warn('Buffer full, dropping span: ' + line_data)
      end
    end

    # Send a list of spans immediately.
    #
    # Have to construct the data manually by calling
    # common.utils.tracing_span_to_line_data()
    #
    # @param spans [List<String>] List of string spans data
    def send_span_now(spans)
      if spans.nil? || spans.empty?
        @spans_invalid.inc
        raise(ArgumentError, 'spans must be non-null and in WF data format')
      end
      @spans_valid.inc(spans.size)
      batch_report(spans, WAVEFRONT_TRACING_SPAN_FORMAT)
    end
  end
end
