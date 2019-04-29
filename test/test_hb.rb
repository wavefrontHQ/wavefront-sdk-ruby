# frozen_string_literal: true

# Test Class for wavefront-client.common.heartbeater
#
# @author mshvol (mvoleti@vmware.com)

require 'test/unit'

require_relative '../lib/wavefront/client/common/heartbeater'
require_relative '../lib/wavefront/client/common/application_tags'
require_relative '../lib/wavefront/client/direct'

include Wavefront

class TestUtils < Test::Unit::TestCase
  class FakeClient < WavefrontDirectIngestionClient
    attr_reader :inputs

    def initialize(input_check)
      @inputs = input_check
    end

    def send_metric(name, value, _timestamp, source, tags)
      data = [name, value, source, tags].freeze
      @inputs[data] -= 1
    end

    def validate
      @inputs.values.inject(:+).zero?
    end
  end

  class FastHeartbeat < HeartbeaterService
    HEARTBEAT_INTERVAL_SECONDS = 0.5
  end

  # Test heartbeater service
  def test_heartbeat
    test_data = { ['~component.heartbeat', 1.0, 'source', { 'application' => 'appname', 'service' => 'svcname', 'cluster' => 'none', 'shard' => 'none', 'component' => 'c1' }] => 1,
                  ['~component.heartbeat', 1.0, 'source', { 'application' => 'appname', 'service' => 'svcname', 'cluster' => 'none', 'shard' => 'none', 'component' => 'c2' }] => 1,
                  ['~component.heartbeat', 1.0, 'source', { 'application' => 'appname', 'service' => 'svcname', 'cluster' => 'none', 'shard' => 'none', 'component' => 'c3' }] => 1 }
    fake_client = FakeClient.new(test_data)

    apptags = ApplicationTags.new('appname', 'svcname')
    fh = FastHeartbeat.new(fake_client, apptags, %w[c1 c2 c3], 'source')

    sleep(1.2)
    fh.stop
    sleep(1)
    assert(fake_client.validate)
  end
end
