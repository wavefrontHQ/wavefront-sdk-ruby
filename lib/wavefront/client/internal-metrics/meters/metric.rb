# frozen_string_literal: true

module Wavefront
  class InternalMetric
    attr_reader :name

    # @param name [String] metric name
    def initialize(name)
      # TODO: sanitize/validate both?
      @name = name.to_sym
    end
  end
end
