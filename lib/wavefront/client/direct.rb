# Wavefront Direct Ingestion Client.
# Sends data directly to Wavefront cluster via the direct ingestion API.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)

require 'uri'
require 'net/http'

require_relative 'common/utils'
require_relative 'common/atomic_integer'
require_relative 'entities/metrics/wavefront_metric_sender'
require_relative 'entities/histogram/wavefront_histogram_sender'
require_relative 'entities/tracing/wavefront_tracing_span_sender'
require_relative 'common/constants'

module Wavefront

  class WavefrontDirectIngestionClient
    include WavefrontMetricSender
    include WavefrontHistogramSender
    include WavefrontTracingSpanSender

    # Construct Direct Client.
    #
    # @param server [String] Server address, Example: https://INSTANCE.wavefront.com
    # @param token [String] Token with Direct Data Ingestion permission granted
    # @param max_queue_size [Integer] Max Queue Size, size of internal data buffer
    # for each data type, 50000 by default.
    # @param batch_size [Integer] Batch Size, amount of data sent by one api call,
    # 10000 by default
    # @param flush_interval_seconds [Integer] Interval flush time, 5 secs by default
    def initialize(server, token, max_queue_size=50000, batch_size=10000, flush_interval_seconds=5)
      @failures = AtomicInteger.new
      @server = server
      @batch_size = batch_size
      @flush_interval_seconds = flush_interval_seconds
      @default_source = "wavefrontDirectSender"
      @metrics_buffer = SizedQueue.new(max_queue_size)
      @histograms_buffer = SizedQueue.new(max_queue_size)
      @tracing_spans_buffer = SizedQueue.new(max_queue_size)
      @headers = {'Content-Type'=>'application/octet-stream',
                      'Content-Encoding'=>'gzip',
                      'Authorization'=>'Bearer ' + token}
      @lock = Mutex.new
      @closed = false
      @task = Thread.new {schedule_task}

      # Start a task to send the metrics periodically
      @task.run
    end

    # Get Total Failure Count
    def failure_count
      @failures.value
    end

    # Flush all buffer before close the client.
    def close
      flush_now
      @lock.synchronize do
        @closed = true
        @task.exit
      end
    end

    def schedule_task
      # Flush every 5 secs by default
      while true && !@closed do
        sleep(@flush_interval_seconds)
        flush_now
      end
    end

    # Flush all the data buffer immediately.
    def flush_now
      internal_flush(@metrics_buffer, WAVEFRONT_METRIC_FORMAT)
      internal_flush(@histograms_buffer, WAVEFRONT_HISTOGRAM_FORMAT)
      internal_flush(@tracing_spans_buffer, WAVEFRONT_TRACING_SPAN_FORMAT)
    end

    # Get all data from one data buffer to a list, and report that list.
    #
    # @param data_buffer [Queue] Data buffer to be flush and sent
    # @param data_format [String] Type of data to be sent
    def internal_flush(data_buffer, data_format)
      data = []
      size = data_buffer.size
      while size > 0 && !data_buffer.empty?
        data << data_buffer.pop
        size -= 1
      end
      batch_report(data, data_format)
    end

    # One api call sending one given string data.

    # @param points [List<String>] List of data in string format, concat by '\n'
    # @param data_format [String] Type of data to be sent
    def report(points, data_format)
      begin
        payload = WavefrontUtil.gzip_compress(points)
        uri = URI.parse(@server)
        https = Net::HTTP.new(uri.host, uri.port)
        https.use_ssl = true
        request = Net::HTTP::Post.new('/report?f=' + data_format, @headers)
        request.body = payload

        response = https.request(request)
        unless [200, 202].include? response.code.to_i
          puts "Error reporting points, Response #{response.code} #{response.message}"
        end
      rescue Exception => error
        @failures.increment
        raise error
      end
    end

    # One api call sending one given list of data.
    #
    # @param batch_line_data [List] List of data to be sent
    # @param data_format [String] Type of data to be sent
    def batch_report(batch_line_data, data_format)
      # Split data into chunks, each with the size of given batch_size
      data_chunks = WavefrontUtil.chunks(batch_line_data, @batch_size)
      data_chunks.each do |batch|
        # report once per batch
        begin
          report(batch.join("\n") + "\n", data_format)
        rescue Exception => error
          puts "Failed to report #{data_format} data points to wavefront. Error: #{error.message}"
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
      line_data = WavefrontUtil.metric_to_line_data(name, value, timestamp, source, tags, @default_source)
      @metrics_buffer.push(line_data)
    end

    # Send a list of metrics immediately.
    #
    # Have to construct the data manually by calling
    # common.utils.metric_to_line_data()
    # @param metrics [List<String>] List of string spans data
    def send_metric_now(metrics)
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
      line_data = WavefrontUtil.histogram_to_line_data(name, centroids, histogram_granularities,
                                      timestamp, source, tags, @default_source)
      @histograms_buffer.push(line_data)
    end

    # Send a list of distribution immediately.
    #
    # Have to construct the data manually by calling
    # common.utils.histogram_to_line_data()
    #
    # @param distributions [List<String>] List of string spans data
    def send_distribution_now(distributions)
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

      line_data = WavefrontUtil.tracing_span_to_line_data(name, start_millis, duration_millis,
                                            source, trace_id, span_id, parents,
                                            follows_from, tags, span_logs, @default_source)
      @tracing_spans_buffer.push(line_data)
    end

    # Send a list of spans immediately.
    #
    # Have to construct the data manually by calling
    # common.utils.tracing_span_to_line_data()
    #
    # @param spans [List<String>] List of string spans data
    def send_span_now(spans)
      batch_report(spans, WAVEFRONT_TRACING_SPAN_FORMAT)
    end
  end
end