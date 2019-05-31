# frozen_string_literal: true

# Test Class for wavefront-client.direct
#
# @author mshvol (mvoleti@vmware.com)

require 'test/unit'

require_relative '../lib/wavefront/client'
require_relative '../lib/wavefront/client/common/application_tags'

include Wavefront

class TestUtils < Test::Unit::TestCase
  class MockDirectClient < WavefrontDirectIngestionClient
    def validate(data)
      ok = true
      @test_data.each do |k, v|
        if data.key?(k) && data[k].strip == v
          data.delete(k)
        else
          puts "missing: #{k} => #{v}"
          ok = false
        end
      end
      @test_data = {}
      data.empty? && ok
    end

    def report(points, data_format)
      points.gsub! /^\"~sdk.*$/, '' # ignore sdk metrics
      @test_data ||= {}
      @test_data[data_format] = points.strip
    end
  end

  def sendall(c)
    c.send_metric('new-york.power.usage', 42_422.0, nil, 'localhost', 'datacenter' => 'dc1')
    c.send_distribution('request.latency', [[30, 20], [5.1, 10]], Set.new(['!M', '!H', '!D']), nil, 'appServer1', 'region' => 'us-west')
    c.send_span(
      'getAllProxyUsers', 1234, 343_500, 'localhost',
      'traceid', 'spanid', ['parentid'], nil,
      { 'application' => 'WavefrontRuby', 'http.method' => 'GET', 'service' => 'TestRuby' }, nil
    )
  end

  # Test heartbeater service
  def test_direct
    test_data = {}
    test_data['wavefront'] = %("new-york.power.usage" 42422.0 source="localhost" "datacenter"="dc1")
    test_data['trace'] = %("getAllProxyUsers" source="localhost" traceId=traceid spanId=spanid parent=parentid "application"="WavefrontRuby" "http.method"="GET" "service"="TestRuby" 1234 343500)
    test_data['histogram'] = %(!M #20 30 #10 5.1 "request.latency" source="appServer1" "region"="us-west"
!H #20 30 #10 5.1 "request.latency" source="appServer1" "region"="us-west"
!D #20 30 #10 5.1 "request.latency" source="appServer1" "region"="us-west")

    c = MockDirectClient.new('server', 'token', flush_interval_seconds: 0.5)
    sendall(c)
    sleep 1
    assert(c.validate(test_data.clone))
    sleep 1
    assert(c.validate({}))
    sendall(c)
    c.close(0.01)
    assert(c.validate(test_data.clone))
  end
end
