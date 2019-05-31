# frozen_string_literal: true

require 'concurrent'
require_relative 'metric'

module Wavefront
  class InternalGauge < InternalMetric
    def initialize(name, &block)
      super(name)
      @value = block
    end
    
    def value
      @value.call.to_f
    end
  end
end
