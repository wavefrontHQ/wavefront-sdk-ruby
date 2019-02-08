# Utils module contains useful function for preparing and processing data.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)

require "zlib"
require 'set'

module Wavefront
  class WavefrontUtil

    # Returns true if the name is empty otherwise false.
    # @param name [String]
    # @return [Boolean]
    def self.is_blank(name)
      name.nil? || name.strip.empty?  ? true : false
    end

    # Split list of data into chunks with fixed batch size.
    #
    # @param data_list [List] List of data
    # @param batch_size [Integer] Batch size of each chunk
    # @return [List] an list of chunks
    def self.chunks(data_list, batch_size)
      data_list.each_slice(batch_size).to_a
    end

    # Compress data using GZIP.
    #
    # @param data [String] Data to compress
    # @return Compressed data
    def self.gzip_compress(data)
      gzip = Zlib::GzipWriter.new(StringIO.new,Zlib::BEST_COMPRESSION)
      gzip << data.encode('utf-8')
      gzip.close.string
    end

    # Sanitize a string, replace whitespace with '-''
    #
    # @param string [String] string to be sanitized
    # @return [String] Sanitized string
    def self.sanitize(string)
      whitespace_sanitized = string.gsub " ", "-"
      # TODO
      if whitespace_sanitized.include? "\""
        "\"" + whitespace_sanitized.gsub!(/\"/, "\\\\\"") + "\""
      end

      "\"" + whitespace_sanitized + "\""
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
      raise(ArgumentError, 'Metrics name cannot be blank') if is_blank(name)
      source = default_source if is_blank(source)
      str_builder = [sanitize(name), value.to_f.to_s]
      str_builder.push(timestamp.to_i.to_s) if timestamp
      str_builder.push("source=" + sanitize(source))

      unless tags.nil?
        tags.each do |key, val|
          raise(ArgumentError,'Metric point tag key cannot be blank') if is_blank(key)
          raise(ArgumentError, 'Metric point tag value cannot be blank') if is_blank(val)
          str_builder.push(sanitize(key) + '=' + sanitize(val))
        end
      end

      str_builder.join(' ') + "\n"
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
      raise(ArgumentError, 'Histogram name cannot be blank') if is_blank(name)
      raise(ArgumentError, 'Histogram granularities cannot be null or empty') if
          histogram_granularities == nil ||  histogram_granularities.empty?
      raise(ArgumentError, 'A distribution should have at least one centroid') if
          centroids == nil ||  centroids.empty?
      source = default_source if is_blank(source)

      line_builder = []

      histogram_granularities.each do |histogram_granularity|
        str_builder = [histogram_granularity]
        str_builder.push(timestamp.to_i.to_s) if timestamp
        centroids.each do |centroid_1, centroid_2|
          str_builder.push("#" + centroid_2.to_s)
          str_builder.push(centroid_1.to_s)
        end
        str_builder.push(sanitize(name))
        str_builder.push("source=" + sanitize(source))
        unless tags.nil?
          tags.each do |key, val|
            raise(ArgumentError, 'Histogram tag key cannot be blank') if is_blank(key)
            raise(ArgumentError, 'Histogram tag value cannot be blank') if is_blank(val)
            str_builder.push(sanitize(key) + '=' + sanitize(val))
          end
        end
        line_builder.push(str_builder.join(' '))
      end
      line_builder.join("\n") + "\n"
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
                                  span_logs, default_source)
      raise(ArgumentError, 'Span name cannot be blank') if is_blank(name)
      source = default_source if is_blank(source)
      str_builder = [sanitize(name),
                    "source=" + sanitize(source),
                    "traceId=" + trace_id.to_s,
                    "spanId=" + span_id.to_s]
      unless parents.nil?
        parents.each do |uuid|
          str_builder.push("parent=" + uuid.to_s)
        end
      end
      unless follows_from.nil?
        follows_from.each do |uuid|
          str_builder.push("followsFrom=" + uuid.to_s)
        end
      end
      unless tags.nil?
        tag_set = Set[]
        tags.each do |key, value|
          raise(ArgumentError, 'Span tag key cannot be blank') if is_blank(key)
          raise(ArgumentError, 'Span tag value cannot be blank') if is_blank(value)
          cur_tag = sanitize(key) + "=" + sanitize(value)
          unless tag_set.include? cur_tag
            str_builder.push(cur_tag)
            tag_set.add(cur_tag)
          end
        end
      end
      str_builder.push(start_millis.to_s)
      str_builder.push(duration_millis.to_s)
      str_builder.join(' ') + "\n"
    end
  end
end