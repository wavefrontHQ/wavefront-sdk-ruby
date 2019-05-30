# frozen_string_literal: true

# Registry class gathers the metric of the service.
# It stores all supported type of the metric e.g. Counters, Gauges and Histograms.
#
require 'concurrent'
require 'json'
require_relative 'meters/counter'
require_relative 'meters/gauge'

module Wavefront
  class InternalMetricsRegistry
    class DuplicateKeyError < StandardError; end

    attr_reader :store, :entity_prefix, :tags

    def initialize(entity_prefix, tags)
      @store = Concurrent::Map.new
      @entity_prefix = entity_prefix + '.'
      @tags = tags
    end

    # Add metric into registry
    #
    # @param metric [Metric] metric to add it can be of any type
    # @return metric object
    def add(metric)
      raise TypeError unless metric.respond_to? :name

      @store.compute_if_absent(metric.name) { metric }
    end

    # Add a new Counter metric to the registry
    #
    # @param name [String] metric name
    # @param initial_value [Integer] metric value
    #
    # @return [Counter] the counter object
    def counter(name, initial_value = 0)
      add(InternalCounter.new(name, initial_value))
    end

    # Add a new Counter metric to the registry
    #
    # @param name [String] metric name
    # @param initial_value [Integer] metric value
    #
    # @return [Gauge] the gauge object
    def gauge(name, &block)
      add(InternalGauge.new(name, &block))
    end

    # Check if metric exists
    #
    # @param name [String] name of the metric
    # @return [Bool]
    def exist?(name)
      @store.key?(name)
    end

    # Get the metric by its name
    #
    # @param name [String] Metric name
    # @return [Metric] the metric value
    def get(name)
      @store[name]
    end

    # Get all the metrics in registry
    # @return list of metrics
    def metrics
      @store.values
    end

    # Return the metric value with suffix
    #
    # @param metric [Metric] metric object
    # @return [Hash] metric list
    def get_metric_fields(metric)
      if metric.class == InternalCounter
        { count: metric.value }
      elsif metric.class == InternalGauge
        { value: metric.value }
      else
        {}
      end
    end
  end
end
