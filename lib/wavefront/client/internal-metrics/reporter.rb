# frozen_string_literal: true

# Wavefront reporter sends data to any wavefront cluster.
# It supports sending data via Direct Ingestion or Proxy.
# Fore more information https://github.com/wavefrontHQ/wavefront-sdk-ruby/blob/master/README.md
#
require_relative '../common/utils'
require_relative 'meters/gauge'
require_relative 'meters/counter'

module Wavefront
  class InternalReporter
    def initialize(client, registry)
      @client = client
      @registry = registry

      @reporting_interval = 60 # seconds
      start
    end

    def start
      @timer&.stop
      @timer = ConstantTickTimer.new(@reporting_interval) { _report }
   end

    def stop(timeout = 1)
      @timer&.stop(timeout)
    end

    private

    def _report
      @registry.metrics.each do |data|
        if (data.class == InternalCounter) || (data.class == InternalGauge)
          result = @registry.get_metric_fields(data)
          @client.send_metric("#{@registry.entity_prefix}#{data.name}#{result.keys[0]}", data.value,
                              (Time.now.to_f * 1000).round, @client.default_source, @registry.tags)
        else
          Wavefront.logger.warn "Metric type not supported: #{data.class}"
        end
      end
    rescue StandardError => e
      Wavefront.logger.error "Internal Reporter error: #{e.message}"
    end
  end
end
