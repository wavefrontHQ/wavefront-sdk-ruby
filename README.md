# wavefront-sdk-ruby  [![Build Status](https://travis-ci.com/yogeshprasad/wavefront-sdk-ruby.svg?branch=master)](https://travis-ci.com/yogeshprasad/wavefront-sdk-ruby)

Wavefront by VMware SDK for Ruby is the core library for sending metrics, histograms and traces data from your Ruby application to Wavefront via proxy or direct ingestion.

## Set Up a Wavefront Client
You can choose to send metrics, histograms, or traces data from your application to the Wavefront service using one of the following techniques:
* Use [direct ingestion](https://docs.wavefront.com/direct_ingestion.html) to send the data directly to the Wavefront service. This is the simplest way to get up and running quickly.
* Use a [Wavefront proxy](https://docs.wavefront.com/proxies.html), which then forwards the data to the Wavefront service. This is the recommended choice for a large-scale deployment that needs resilience to internet outages, control over data queuing and filtering, and more.

There are two type of `Wavefront Client`, You can use any client that corresponds to your choice:
* Option 1: [Create a `WavefrontDirectIngestionClient`](#option-1-create-a-wavefrontdirectingestionclient) to send data directly to a Wavefront service.
* Option 2: [Create a `WavefrontProxyClient`](#option-2-create-a-wavefrontproxyclient) to send data to a Wavefront proxy.

### Option 1. Create a WavefrontDirectIngestionClient
To create a `WavefrontDirectIngestionClient`, you build it with the information it needs to send data directly to Wavefront.

#### Step 1. Obtain Wavefront Access Information
Gather the following access information:

* Identify the URL of your Wavefront instance. This is the URL you connect to when you log in to Wavefront, typically something like `https://<domain>.wavefront.com`.
* In Wavefront, verify that you have Direct Data Ingestion permission, and [obtain an API token](http://docs.wavefront.com/wavefront_api.html#generating-an-api-token).

#### Step 2. Initialize the WavefrontDirectIngestionClient
You instantiate a `WavefrontDirectIngestionClient` with the access information you obtained in Step 1.

You can optionally pass below parameters to tune the following ingestion properties:

* Max queue size - Internal buffer capacity of the `WavefrontSender`. Any data in excess of this size is dropped.
* Flush interval - Interval for flushing data from the `WavefrontSender` directly to Wavefront.
* Batch size - Amount of data to send to Wavefront in each flush interval.

Together, the batch size and flush interval control the maximum theoretical throughput of the `WavefrontSender`. You should override the defaults _only_ to set higher values.

```ruby
require_relative 'direct'
# Construct Wavefront direct ingestion client.
#
# server [String] Server address, Example: https://INSTANCE.wavefront.com
# token [String] Token with Direct Data Ingestion permission granted
# max_queue_size [Integer] Max Queue Size, size of internal data buffer for each data type, 50000 by default.
# batch_size [Integer] Batch Size, amount of data sent by one api call, 10000 by default
# flush_interval_seconds [Integer] Interval flush time, 5 secs by default
client = Wavefront::WavefrontDirectIngestionClient.new(server, token)

 ```

### Option 2. Create a WavefrontProxyClient

**Note:** Before your application can use a `WavefrontProxyClient`, you must [set up and start a Wavefront proxy](https://github.com/wavefrontHQ/java/tree/master/proxy#set-up-a-wavefront-proxy).

To create a `WavefrontProxyClient`, you instantiate it with the information it needs to send data to the Wavefront proxy, including:

* The name of the host that will run the Wavefront proxy.
* One or more proxy listening ports to send data to. The ports you specify depend on the kinds of data you want to send (metrics, histograms, and/or traces data). You must specify at least one listener port.
* Optional settings for tuning communication with the proxy.


```ruby
require_relative 'proxy'
# Construct Wavefront proxy client.
#
# proxy_host [String] Hostname of the Wavefront proxy, 2878 by default
# metrics_port [Integer] Metrics Port on which the Wavefront proxy is listening on
# distribution_port [Integer] Distribution Port on which the Wavefront proxy is listening on
# tracing_port [Integer] Tracing Port on which the Wavefront proxy is listening on
client = Wavefront::WavefrontProxyClient.new(proxy_host, metrics_port, distribution_port, tracing_port)

 ```

## Send Data to Wavefront

 To send data to Wavefront using the `Wavefront client` you instantiated:

### Metrics

 ```ruby
# Wavefront Metrics Data format
# <metricName> <metricValue> [<timestamp>] source=<source> [pointTags]
# Example: "new-york.power.usage 42422 1533529977 source=localhost datacenter=dc1"
client.send_metric("new-york.power.usage", 42422.0, nil, "localhost", {"datacenter"=>"dc1"})
```

### Distributions (Histograms)

```ruby
# Wavefront Histogram Data format
# {!M | !H | !D} [<timestamp>] #<count> <mean> [centroids] <histogramName> source=<source>
# [pointTags]
# Example: You can choose to send to at most 3 bins: Minute, Hour, Day
# "!M 1533529977 #20 30.0 #10 5.1 request.latency source=appServer1 region=us-west"
# "!H 1533529977 #20 30.0 #10 5.1 request.latency source=appServer1 region=us-west"
# "!D 1533529977 #20 30.0 #10 5.1 request.latency source=appServer1 region=us-west"
client.send_distribution("request.latency",
                         [[30, 20], [5.1, 10]], Set.new([DAY, HOUR, MINUTE]), nil, "appServer1", {"region"=>"us-west"})
```

### Tracing Spans

```ruby
require 'securerandom'
# Wavefront Tracing Span Data format
# <tracingSpanName> source=<source> [pointTags] <start_millis> <duration_milliseconds>
# Example: "getAllUsers source=localhost
#           traceId=7b3bf470-9456-11e8-9eb6-529269fb1459
#           spanId=0313bafe-9457-11e8-9eb6-529269fb1459
#           parent=2f64e538-9457-11e8-9eb6-529269fb1459
#           application=Wavefront http.method=GET
#           1533529977 343500"
client.send_span(
      "getAllProxyUsers", Time.now.to_i, 343500, "localhost",
      SecureRandom.uuid, SecureRandom.uuid, [SecureRandom.uuid], nil,
      {"application"=>"WavefrontRuby", "http.method"=>"GET", "service"=>"TestRuby"}, nil)
```

## Close the WavefrontSender
Remember to flush the buffer and close the sender before shutting down your application.
```ruby
# If there are any failures observed while sending metrics/histograms/tracing-spans above,
# you get the total failure count using the below API
total_failures = client.failure_count

# close the sender connection before shutting down application
# this will flush in-flight buffer and close connection
client.close
```

