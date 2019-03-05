# Interface of Histogram Sender for both clients.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)

module WavefrontHistogramSender
  # Send Distribution Data.
  #
  # Wavefront Histogram Data format
  #   {!M | !H | !D} [<timestamp>] #<count> <mean> [centroids]
  #     <histogramName> source=<source> [pointTags]
  #
  # Example:
  #   '!M 1533531013 #20 30.0 #10 5.1 request.latency
  #   source=appServer1 region=us-west'
  #
  # @param name [String] Histogram Name
  # @param centroids [List] List of centroids(pairs)
  # @param histogram_granularities [Set] Histogram Granularities
  # @param timestamp [Long] Timestamp
  # @param source [String] Source
  # @param tags [Hash] Tags

  def send_distribution(name, centroids, histogram_granularities,
                        timestamp, source, tags)
    raise NotImplementedError, 'send_distribution has not been implemented.'
  end

  # Send a list of distributions immediately.
  #
  # Have to construct the data manually by calling
  # common.utils.histogram_to_line_data()
  #
  # @param distributions [List<String>] List of string distribution data
  def send_distribution_now(distributions)
    raise NotImplementedError, 'send_distribution_now has not been implemented.'
  end
end

