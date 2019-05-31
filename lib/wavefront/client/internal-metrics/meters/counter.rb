# frozen_string_literal: true

require 'concurrent'
require_relative 'metric'

module Wavefront
  class InternalCounter < InternalMetric
    # @param name [string] Metric name
    # @param point_tags [Hash] Point tags for counter
    # @param initial_value [Integer] Initial value for counter
    def initialize(name, initial_value = 0)
      super(name)
      unless initial_value.is_a? Integer
        raise RangeError, "Counter needs an integer. Given #{val}"
      end

      @value = Concurrent::AtomicFixnum.new(initial_value)
    end

    # Return current counter value
    def value
      @value.value
    end

    # Increment counter by val (default is 1)
    #
    # @param val [Integer] Counter increment by val
    def inc(val = 1)
      @value.increment(val.to_i)
    end
  end
end
