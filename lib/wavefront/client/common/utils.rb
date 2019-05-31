# frozen_string_literal: true

# Utils module contains useful function for preparing and processing data.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)

require 'zlib'
require 'set'
require 'concurrent'

module Wavefront
  @@wflog = Logger.new(STDERR)

  def self.logger
    @@wflog
  end

  class WavefrontUtil
    # Returns true if the string is empty otherwise false.
    # @param name [String]
    # @return [Boolean]
    def self.blank?(str) # only works on strings
      str.nil? || str.to_s.strip.empty?
    end

    # Split list of data into chunks with fixed batch size.
    #
    # @param data_list [List] List of data
    # @param batch_size [Integer] Size of each chunk
    # @return [Enumerable] a list of chunks
    def self.chunks(data_list, batch_size)
      data_list.each_slice(batch_size)
    end

    # Compress data using GZIP.
    #
    # @param data [String] Data to compress
    # @return Compressed data
    def self.gzip_compress(data)
      gzip = Zlib::GzipWriter.new(StringIO.new, Zlib::BEST_COMPRESSION)
      gzip << data.encode('utf-8')
      gzip.close.string
    end

    # Sanitize a string, replace whitespace with '-''
    #
    # @param string [String] string to be sanitized
    # @return [String] Sanitized string
    def self.sanitize(item)
      whitespace_sanitized = item.to_s.gsub /\s+/, '-'
      whitespace_sanitized.gsub!(/\"+/, '\\\\"')
      '"' + whitespace_sanitized + '"'
    end

    # Metric Data to String.
    #
    # Wavefront Metrics Data format
    # <metricName> <metricValue> [<timestamp>] source=<source> [pointTags]
    # Example: 'new-york.power.usage 42422 1533531013 source=localhost
    #          datacenter=dc1'
    #
    # @param name [String] Metric Name
    # @param value [Float] Metric Value
    # @param timestamp [Long] Timestamp
    # @param source [String] Source
    # @param tags [Hash] Tags
    # @param default_source [String]
    # @return  [String] String data of metrics
    def self.metric_to_line_data(name, value, timestamp, source, tags, default_source)
      raise(ArgumentError, 'Metrics name cannot be blank') if blank?(name)

      source = sanitize(blank?(source) ? default_source : source)

      core = ["#{sanitize(name)} #{value&.to_f || 0} #{timestamp&.to_i}".rstrip, "source=#{source}"]
      tags2 = make_tags(tags)

      (core + tags2).join(' ') + "\n"
    end

    # Wavefront Histogram Data format.
    #
    # {!M | !H | !D} [<timestamp>] #<count> <mean> [centroids] <histogramName>
    # source=<source> [pointTags]
    # Example: '!M 1533531013 #20 30.0 #10 5.1 request.latency source=appServer1
    #          region=us-west'
    #
    # @param name [String] Histogram Name
    # @param centroids [List] List of centroids(pairs)
    # @param histogram_granularities [Set] Histogram Granularities
    # @param timestamp [Long] Timestamp
    # @param source [String] Source
    # @param tags [Hash] Tags
    # @param default_source [String] Default Source
    # @return [String] String data of Histogram
    def self.histogram_to_line_data(name, centroids, histogram_granularities, timestamp, source, tags, default_source)
      raise(ArgumentError, 'Histogram name cannot be blank') if blank?(name)
      raise(ArgumentError, 'Histogram granularities cannot be null or empty') if histogram_granularities.nil? || histogram_granularities.empty?
      raise(ArgumentError, 'Histogram should have at least one centroid') if
          centroids.nil? || centroids.empty?

      source = sanitize(blank?(source) ? default_source : source)

      cen_str = Array(centroids)
                .reject { |p| p.nil? || p.empty? }
                .map { |mean, count| "##{count} #{mean}" }
                .join(' ')

      tags2 = make_tags(tags).join(' ')

      all = "#{timestamp} #{cen_str} #{sanitize(name)} source=#{source} #{tags2}".strip

      Array(histogram_granularities).map { |g| "#{g} #{all}\n" }.join
    end

    #  Wavefront Tracing Span Data format.
    #
    #  <tracingSpanName> source=<source> [pointTags] <start_millis>
    #  <duration_milli_seconds>
    #  Example: "getAllUsers source=localhost
    # traceId=7b3bf470-9456-11e8-9eb6-529269fb1459
    # spanId=0313bafe-9457-11e8-9eb6-529269fb1459
    # parent=2f64e538-9457-11e8-9eb6-529269fb1459
    # application=Wavefront http.method=GET
    # 1533531013 343500
    #
    # @param name [String] Span Name
    # @param start_millis [Long] Start time
    # @param duration_millis [Long] Duration time
    # @param source [String] Source
    # @param trace_id [UUID] Trace ID
    # @param span_id [UUID] Span ID
    # @param parents [UUID] Parents Span ID
    # @param follows_from [UUID] Follows Span ID
    # @param tags [List] Tags
    # @param span_logs [List] Span Log
    # @param default_source [String] Default Source
    # @return [String] String data of tracing span
    def self.tracing_span_to_line_data(name, start_millis, duration_millis, source,
                                       trace_id, span_id, parents, follows_from, tags,
                                       _span_logs, default_source)
      raise(ArgumentError, 'Span name cannot be blank') if blank?(name)
      raise(ArgumentError, 'Trace ID cannot be blank') if blank?(trace_id)
      raise(ArgumentError, 'Span ID cannot be blank') if blank?(span_id)

      source = sanitize(blank?(source) ? default_source : source)

      parents2 = Array(parents)
                 .reject { |p| blank?(p) }
                 .map { |p| "parent=#{p}" }

      follows2 = Array(follows_from)
                 .reject { |p| blank?(p) }
                 .map { |p| "followsFrom=#{p}" }

      tags2 = make_tags(tags)

      core = Array("source=#{source} traceId=#{trace_id} spanId=#{span_id}")
      all_tags = (core + parents2 + follows2 + tags2).join(' ')

      "#{sanitize(name)} #{all_tags} #{start_millis&.to_i} #{duration_millis&.to_i || 0}\n"
    end

    private

    def self.make_tags(tags)
      Array(tags)
        .map do |k, v| # only use first two values
        raise(ArgumentError, 'Span tag key cannot be blank') if blank?(k)
        raise(ArgumentError, 'Span tag value cannot be blank') if blank?(v)

        "#{sanitize(k)}=#{sanitize(v)}"
      end
        .uniq # remove duplicate tags
    end
  end

  class ConstantTickTimer
    def initialize(interval, run_now = false, executor = Concurrent::SingleThreadExecutor.new, &block)
      raise ArgumentError 'interval must be > 0' if interval <= 0
      raise ArgumentError 'block is mandatory' if block.nil?

      @stopev = Concurrent::Event.new
      @st = executor

      nex = run_now ? 0 : interval

      task = lambda do
        @stopev.wait(nex)
        if @stopev.set?
          @st.shutdown
          return
        end

        begin
          s = Concurrent.monotonic_time
          block.call
        rescue StandardError => e
          Wavefront.logger.error "Error in Timer Task: #{e}\n\t#{e.backtrace.join("\n\t")}"
        ensure
          d = Concurrent.monotonic_time - s
          r = (d / interval).floor + 1
          nex = r * interval - d
          @st.post &task # check error?
        end
      end

      @st.post &task # start timer
    end

    def stop(timeout = 5)
      @stopev.set
      @st.wait_for_termination(timeout)
      unless @st.shutdown?
        @st.kill
        Wavefront.logger.warn 'Warning: Timer killed because stop exceeded timeout'
      end
    end
  end

  class EarlyTickTimer
    def initialize(interval, run_now = false, executor = Concurrent::SingleThreadExecutor.new, &block)
      raise ArgumentError 'interval must be > 0' if interval <= 0
      raise ArgumentError 'block is mandatory' if block.nil?

      @stopev = Concurrent::Event.new
      @st = executor

      nex = run_now ? 0.0001 : interval

      task = lambda do
        @stopev.wait(nex)
        if @stopev.set?
          @st.shutdown
          return
        end

        begin
          s = Concurrent.monotonic_time
          block.call
        rescue StandardError => e
          Wavefront.logger.error "Error in Timer Task: #{e}\n\t#{e.backtrace.join("\n\t")}"
        ensure
          d = Concurrent.monotonic_time - s - interval
          nex = d >= 0 ? 0.00001 : -d
          @st.post &task # check error?
        end
      end

      @st.post &task # start timer
    end

    def stop(timeout = 5)
      @stopev.set
      @st.wait_for_termination(timeout)
      unless @st.shutdown?
        @st.kill
        Wavefront.logger.warn 'Warning: Timer killed because stop exceeded timeout'
      end
    end
  end

  class SendError < StandardError
    attr_reader :cause
    def initialize(error)
      @cause = error
      super(@cause.to_s)
    end
  end
end
