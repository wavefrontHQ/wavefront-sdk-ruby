# All Ruby-sdk constants.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)

module Wavefront
  # Tag key for defining an application.
  APPLICATION_TAG_KEY = 'application'.freeze

  # Tag key for defining a cluster.
  CLUSTER_TAG_KEY = 'cluster'.freeze

  # Tag key for defining a shard.
  SHARD_TAG_KEY = 'shard'.freeze

  # Tag key  for defining a service.
  SERVICE_TAG_KEY = 'service'.freeze

  # ∆: INCREMENT
  DELTA_PREFIX = '∆'.freeze # '\u2206'

  # Δ: GREEK CAPITAL LETTER DELTA
  DELTA_PREFIX_2 = 'Δ'.freeze # '\u0394'

  # Use this format to send metric data to Wavefront.
  WAVEFRONT_METRIC_FORMAT = 'wavefront'.freeze

  # Use this format to send histogram data to Wavefront.
  WAVEFRONT_HISTOGRAM_FORMAT = 'histogram'.freeze

  # Use this format to send tracing data to Wavefront.
  WAVEFRONT_TRACING_SPAN_FORMAT = 'trace'.freeze
end