# frozen_string_literal: true

# All Ruby-sdk constants.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)

module Wavefront
  # Tag key for defining an application.
  APPLICATION_TAG_KEY = 'application'

  # Tag key for defining a cluster.
  CLUSTER_TAG_KEY = 'cluster'

  # Tag key for defining a shard.
  SHARD_TAG_KEY = 'shard'

  # Tag key  for defining a service.
  SERVICE_TAG_KEY = 'service'

  # ∆: INCREMENT
  DELTA_PREFIX = '∆' # '\u2206'

  # Δ: GREEK CAPITAL LETTER DELTA
  DELTA_PREFIX_2 = 'Δ' # '\u0394'

  # Use this format to send metric data to Wavefront.
  WAVEFRONT_METRIC_FORMAT = 'wavefront'

  # Use this format to send histogram data to Wavefront.
  WAVEFRONT_HISTOGRAM_FORMAT = 'histogram'

  # Use this format to send tracing data to Wavefront.
  WAVEFRONT_TRACING_SPAN_FORMAT = 'trace'

  # Heartbeat metric.
  HEART_BEAT_METRIC = '~component.heartbeat'

  # Tag key for defining a component.
  COMPONENT_TAG_KEY = 'component'

  # Null value emitted for optional undefined tags.
  NULL_TAG_VAL = 'none'
end
