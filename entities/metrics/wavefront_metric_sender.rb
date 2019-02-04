# Interface of Metric Sender for both clients.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)

module WavefrontMetricSender
  # ∆: INCREMENT
  DELTA_PREFIX = '∆'.freeze # '\u2206'

  # Δ: GREEK CAPITAL LETTER DELTA
  DELTA_PREFIX_2 = 'Δ'.freeze # '\u0394'

  # Send Metric Data.
  # Wavefront Metrics Data format
  #   <metricName> <metricValue> [<timestamp>] source=<source> [pointTags]
  #
  # Example:
  #   "new-york.power.usage 42422 1533531013 source=localhost datacenter=dc1"

  # @param name [String] Metric Name
  # @param value [Float] Metric Value
  # @param timestamp [Long] Timestamp
  # @param source [String] Source
  # @param tags [Hash] Tags
  def send_metric(name, value, timestamp, source, tags)
    raise NotImplementedError, 'send_metric has not been implemented.'
  end

  # Send a list of metrics immediately.
  #
  # Have to construct the data manually by calling
  # common.utils.metric_to_line_data()
  #
  # @param metrics [List<String>] List of string spans data
  def send_metric_now(metrics)
    raise NotImplementedError, 'send_metric_now has not been implemented.'
  end

  # Send Delta Counter Data.
  #
  # @param name [String] Metric Name
  # @param value [Float] Metric Value
  # @param source [String] Source
  # @param tags [Hash] Tags
  def send_delta_counter(name, value, source, tags)
    if !name.start_with?(DELTA_PREFIX) && !name.start_with?(DELTA_PREFIX_2)
      name = DELTA_PREFIX + name
    end
    send_metric(name, value, None, source, tags)
  end
end
