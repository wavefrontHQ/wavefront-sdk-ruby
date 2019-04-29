# frozen_string_literal: true

require 'socket'
require_relative './application_tags'

module Wavefront
  class HeartbeaterService
    HEARTBEAT_INTERVAL_SECONDS = 60 * 5

    def initialize(sender, application_tags, components, source = Socket.gethostname)
      @sender = sender
      @components_tags = Array(components).map do |component|
        {
          APPLICATION_TAG_KEY => application_tags.application,
          SERVICE_TAG_KEY => application_tags.service,
          CLUSTER_TAG_KEY => application_tags.cluster || NULL_TAG_VAL,
          SHARD_TAG_KEY => application_tags.shard || NULL_TAG_VAL,
          COMPONENT_TAG_KEY => component
        }
      end
      @source = source
      @closed = false
      @task = nil
      _start
    end

    def stop
      @closed = true
      @task&.kill&.join
      @task = nil
    end

    private

    def _start
      @task = Thread.new { _run }
    end

    def _run
      until @closed
        Thread.handle_interrupt(RuntimeError => :never) do
          _beat
        end
        sleep(HEARTBEAT_INTERVAL_SECONDS)
      end
    end

    def _beat
      @components_tags.each do |comp_tags|
        @sender.send_metric(HEART_BEAT_METRIC, 1.0, (Time.now.to_f * 1000.0).to_i, @source, comp_tags)
      end
    rescue StandardError => e
      # TODO: Use logger instead of warn?
      warn "Error sending heartbeat. #{e}\n\t#{e.backtrace.join("\n\t")}"
    end
  end
end
