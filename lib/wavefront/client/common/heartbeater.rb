# frozen_string_literal: true

require_relative './application_tags'
require_relative './utils'

module Wavefront
  class HeartbeaterService
    HEARTBEAT_INTERVAL = 60 * 5 # in seconds

    def initialize(sender, application_tags, components, source = Socket.gethostname)
      @sender = sender
      @source = source
      @components_tags = Array(components).map do |component|
        {
          APPLICATION_TAG_KEY => application_tags.application,
          SERVICE_TAG_KEY => application_tags.service,
          CLUSTER_TAG_KEY => application_tags.cluster || NULL_TAG_VAL,
          SHARD_TAG_KEY => application_tags.shard || NULL_TAG_VAL,
          COMPONENT_TAG_KEY => component
        }
      end
      _start
    end

    def stop
      @timer&.stop
    end

    private

    def _start
      @timer&.stop
      @timer = ConstantTickTimer.new(self.class::HEARTBEAT_INTERVAL, true) { _beat }
    end

    def _beat
      @components_tags.each do |comp_tags|
        @sender.send_metric(HEART_BEAT_METRIC, 1.0, (Time.now.to_f * 1000.0).round, @source, comp_tags)
      end
    rescue StandardError => e
      Wavefront.logger.warn "Error sending heartbeat. #{e}\n\t#{e.backtrace.join("\n\t")}"
    end
  end
end
