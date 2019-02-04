# Test Class for wavefront_ruby_sdk.common.utils.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)

require "test/unit"
require 'set'
require 'securerandom'

require_relative '../common/utils'
require_relative '../proxy'
require_relative '../direct'

class TestUtils < Test::Unit::TestCase
  # Test wavefront_ruby_sdk.common.utils.sanitize
  def test_sanitize
    assert_equal('"hello"', Wavefront::WavefrontUtil.sanitize("hello"))
    assert_equal('"hello-world"', Wavefront::WavefrontUtil.sanitize("hello world"))
    assert_equal('"hello.world"', Wavefront::WavefrontUtil.sanitize("hello.world"))
    assert_equal('"hello\\"world\\""', Wavefront::WavefrontUtil.sanitize('hello"world"'))
    assert_equal('"hello\'world"', Wavefront::WavefrontUtil.sanitize("hello'world"))
  end

  # Test wavefront_ruby_sdk.common.utils.metric_to_line_data
  def test_metric_to_line_data
    assert_equal("\"new-york.power.usage\" 42422.0 1493773500 source=\"localhost\" \"datacenter\"=\"dc1\"\n",
                 Wavefront::WavefrontUtil.metric_to_line_data("new-york.power.usage", 42422, 1493773500,
                                                   "localhost", {"datacenter"=>"dc1"},
                                                   "defaultSource"))
    # null timestamp
    assert_equal("\"new-york.power.usage\" 42422.0 source=\"localhost\" " +
                     "\"datacenter\"=\"dc1\"\n",
                 Wavefront::WavefrontUtil.metric_to_line_data("new-york.power.usage", 42422, nil,
                                                   "localhost", {"datacenter"=>"dc1"},
                                                   "defaultSource"))
    # null tags
    assert_equal("\"new-york.power.usage\" 42422.0 1493773500 source=\"localhost\"\n",
                 Wavefront::WavefrontUtil.metric_to_line_data("new-york.power.usage", 42422, 1493773500,
                                                   "localhost", nil, "defaultSource"))
    # null tags and null timestamp
    assert_equal("\"new-york.power.usage\" 42422.0 source=\"localhost\"\n",
                 Wavefront::WavefrontUtil.metric_to_line_data("new-york.power.usage", 42422, nil, "localhost",
                                                   nil, "defaultSource"))
  end

  # Test wavefront_ruby_sdk.common.utils.histogram_to_line_data
  def test_histogram_to_line_data
    assert_equal("!M 1493773500 #20 30.0 #10 5.1 \"request.latency\" source=\"appServer1\" " +
                     "\"region\"=\"us-west\"\n",
                 Wavefront::WavefrontUtil.histogram_to_line_data("request.latency", [[30.0, 20], [5.1, 10]],
                                                      Set.new([MINUTE]), 1493773500, "appServer1",
                                                      {"region"=>"us-west"}, "defaultSource"))
    # null timestamp
    assert_equal("!M #20 30.0 #10 5.1 \"request.latency\" source=\"appServer1\" " +
                     "\"region\"=\"us-west\"\n",
                 Wavefront::WavefrontUtil.histogram_to_line_data("request.latency", [[30.0, 20], [5.1, 10]],
                                                      Set.new([MINUTE]), nil, "appServer1",
                                                      {"region"=>"us-west"}, "defaultSource"))
    # null tags
    assert_equal("!M 1493773500 #20 30.0 #10 5.1 \"request.latency\" source=\"appServer1\"\n",
                 Wavefront::WavefrontUtil.histogram_to_line_data("request.latency", [[30.0, 20], [5.1, 10]],
                                                      Set.new([MINUTE]), 1493773500, "appServer1",
                                                      nil,"defaultSource"))
    # empty centroids
    assert_raise(ArgumentError) {
      Wavefront::WavefrontUtil.histogram_to_line_data("request.latency", [],
                                           Set.new([MINUTE]), 1493773500,
                                           "appServer1", nil,
                                           "defaultSource")}
    # no histogram granularity specified
    assert_raise(ArgumentError){
      Wavefront::WavefrontUtil.histogram_to_line_data("request.latency",
                                           [[30.0, 20], [5.1, 10]], nil,
                                           1493773500, "appServer1", nil,
                                           "defaultSource")}
    # multiple granularities
    assert_equal(["!M 1493773500 #20 30.0 #10 5.1 \"request.latency\" source=\"appServer1\" " +
                      "\"region\"=\"us-west\"\n" +
                      "!H 1493773500 #20 30.0 #10 5.1 \"request.latency\" source=\"appServer1\" " +
                      "\"region\"=\"us-west\"\n" +
                      "!D 1493773500 #20 30.0 #10 5.1 \"request.latency\" source=\"appServer1\" " +
                      "\"region\"=\"us-west\"\n"],
                 Wavefront::WavefrontUtil.histogram_to_line_data("request.latency", [[30.0, 20], [5.1, 10]],
                                                      Set.new([MINUTE, HOUR, DAY]), 1493773500,
                                                      "appServer1", {"region"=>"us-west"},
                                                      "defaultSource").split("\\n"))
  end

  # Test wavefront_ruby_sdk.common.utils.tracing_span_to_line_data
  def test_tracing_span_to_line_data
    assert_equal("\"getAllUsers\" source=\"localhost\" " +
                     "traceId=7b3bf470-9456-11e8-9eb6-529269fb1459 spanId=0313bafe-9457-11e8-9eb6-529269fb1459 " +
                     "parent=2f64e538-9457-11e8-9eb6-529269fb1459 " +
                     "followsFrom=5f64e538-9457-11e8-9eb6-529269fb1459 " +
                     "\"application\"=\"Wavefront\" " +
                     "\"http.method\"=\"GET\" 1493773500 343500\n",
                 Wavefront::WavefrontUtil.tracing_span_to_line_data(
                     "getAllUsers", 1493773500, 343500, "localhost",
                     "7b3bf470-9456-11e8-9eb6-529269fb1459",
                     "0313bafe-9457-11e8-9eb6-529269fb1459",
                     ["2f64e538-9457-11e8-9eb6-529269fb1459"],
                     ["5f64e538-9457-11e8-9eb6-529269fb1459"],
                     [["application", "Wavefront"], ["http.method", "GET"]],
                     nil, "defaultSource"))

    # null followsFrom
    assert_equal("\"getAllUsers\" source=\"localhost\" " +
                     "traceId=7b3bf470-9456-11e8-9eb6-529269fb1459 spanId=0313bafe-9457-11e8-9eb6-529269fb1459 " +
                     "parent=2f64e538-9457-11e8-9eb6-529269fb1459 \"application\"=\"Wavefront\" " +
                     "\"http.method\"=\"GET\" 1493773500 343500\n",
                 Wavefront::WavefrontUtil.tracing_span_to_line_data(
                     "getAllUsers", 1493773500, 343500, "localhost",
                     "7b3bf470-9456-11e8-9eb6-529269fb1459",
                     "0313bafe-9457-11e8-9eb6-529269fb1459",
                     ["2f64e538-9457-11e8-9eb6-529269fb1459"],
                     [],
                     [["application", "Wavefront"], ["http.method", "GET"]],
                     nil, "defaultSource"))

    # root span
    assert_equal("\"getAllUsers\" source=\"localhost\" " +
                     "traceId=7b3bf470-9456-11e8-9eb6-529269fb1459 spanId=0313bafe-9457-11e8-9eb6-529269fb1459 " +
                     "\"application\"=\"Wavefront\" " +
                     "\"http.method\"=\"GET\" 1493773500 343500\n",
                 Wavefront::WavefrontUtil.tracing_span_to_line_data(
                     "getAllUsers", 1493773500, 343500, "localhost",
                     "7b3bf470-9456-11e8-9eb6-529269fb1459",
                     "0313bafe-9457-11e8-9eb6-529269fb1459", nil, nil,
                       [["application", "Wavefront"], ["http.method", "GET"]],
                   nil, "defaultSource"))

    # duplicate tags
    assert_equal("\"getAllUsers\" source=\"localhost\" " +
                     "traceId=7b3bf470-9456-11e8-9eb6-529269fb1459 spanId=0313bafe-9457-11e8-9eb6-529269fb1459 " +
                     "\"application\"=\"Wavefront\" " +
                     "\"http.method\"=\"GET\" 1493773500 343500\n",
                 Wavefront::WavefrontUtil.tracing_span_to_line_data(
            "getAllUsers", 1493773500, 343500, "localhost",
            "7b3bf470-9456-11e8-9eb6-529269fb1459",
            "0313bafe-9457-11e8-9eb6-529269fb1459", nil, nil,
            [["application", "Wavefront"], ["http.method", "GET"],
             ["application", "Wavefront"]],
            nil, "defaultSource"))

    # null tags
    assert_equal("\"getAllUsers\" source=\"localhost\" " +
                     "traceId=7b3bf470-9456-11e8-9eb6-529269fb1459 spanId=0313bafe-9457-11e8-9eb6-529269fb1459 " +
                     "1493773500 343500\n",
                 Wavefront::WavefrontUtil.tracing_span_to_line_data(
            "getAllUsers", 1493773500, 343500, "localhost",
            "7b3bf470-9456-11e8-9eb6-529269fb1459",
            "0313bafe-9457-11e8-9eb6-529269fb1459",
            nil, nil, nil, nil, "defaultSource"))
  end
end
