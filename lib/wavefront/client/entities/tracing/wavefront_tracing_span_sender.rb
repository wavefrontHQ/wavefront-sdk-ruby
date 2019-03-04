# Tracing Span Sender Interface for both Clients.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)

module WavefrontTracingSpanSender

  # Send span data via proxy.
  #
  # Wavefront Tracing Span Data format
  #   <tracingSpanName> source=<source> [pointTags] <start_millis>
  #      <duration_milli_seconds>
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
  # @param span_logs: Span Log
  def send_span(name, start_millis, duration_millis, source, trace_id,
                span_id, parents, follows_from, tags, span_logs)
    raise NotImplementedError, 'send_span has not been implemented.'
  end

  # Send a list of spans immediately.
  #
  # Have to construct the data manually by calling
  # common.utils.metric_to_line_data()
  #
  # @param spans [List<String>] List of string spans data
  def send_span_now(spans)
    raise NotImplementedError, 'has not been implemented.'
  end
end
