# frozen_string_literal: true

# Connection Handler class for sending data to a Wavefront proxy.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)

require_relative 'utils'
require 'net/tcp_client'

# Connection Handler.
# For sending data to a Wavefront proxy listening on a given port.
module Wavefront
  class ProxyConnectionHandler
    # Construct ProxyConnectionHandler.
    # @param address [String] Proxy Address
    # @param port [Integer] Proxy Port
    def initialize(address, port, internal_store, retries: 2, retry_interval: 0.5)
      @internal_store = internal_store
      @lock = Mutex.new

      @client_options = {
        server: "#{address}:#{port}",
        # disable client retries as we collect failure counts
        connect_retry_count: 0,
        retry_count: 0
        # use default timeouts
        #   connect: 10s; write: 60s
      }.freeze
      @retries = retries
      @retry_interval = retry_interval

      @errors = @internal_store.counter('errors')
      @connect_errors = @internal_store.counter('connect.errors')

      # connect now to reduce send latency
      connect
    end

    # Open a socket connection to the given address:port
    def connect
      last_error = nil
      @retries.times do |_ri|
        begin
          @lock.synchronize { @client ||= Net::TCPClient.new(@client_options) }
          try_reconnect
          break
        rescue Net::TCPClient::ConnectionFailure => e
          Wavefront.logger.error "Connection failure: #{e.cause}"
          @connect_errors.inc
          last_error = e.cause
        rescue Net::TCPClient::ConnectionTimeout, Net::TCPClient::WriteTimeout => e
          Wavefront.logger.warn "Warning: #{e.cause}"
          @connect_errors.inc
          last_error = e.cause
        rescue StandardError => e
          Wavefront.logger.error "Unexpected Error: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
          last_error = e
        ensure
          sleep @retry_interval unless last_error.nil?
        end
      end
      if last_error
        @errors.inc
        raise SendError, last_error
      end
    end

    # Close socket if it's open now.
    def close
      @client&.close
    end

    def failure_count
      @errors.value
    end

    # Send data via proxy.
    # @param line_data [String] Data to be sent
    # @param reconnect [Boolean] If it's the second time trying to send data
    def send_data(line_data)
      last_error = nil
      @retries.times do |_ri|
        begin
          try_reconnect # client.write auto-reconnects only if retry counts > 0
          @client.write(line_data.encode('utf-8')) # assuming this is atomic
          break
        rescue Net::TCPClient::ConnectionFailure => e
          Wavefront.logger.error "Connection failure: #{e.cause}"
          @connect_errors.inc
          last_error = e.cause
        rescue Net::TCPClient::ConnectionTimeout, Net::TCPClient::WriteTimeout => e
          Wavefront.logger.warn "Warning: #{e.cause}"
          @connect_errors.inc
          last_error = e.cause
        rescue StandardError => e
          Wavefront.logger.error "Unexpected Error: #{e.message}\n\t#{e.backtrace.join("\n\t")}"
          last_error = e
        ensure
          sleep @retry_interval unless last_error.nil?
        end
      end
      if last_error
        @errors.inc
        raise SendError, last_error
      end
    end

    private

    def try_reconnect
      # double checked locking as reconnect should be a rare event
      if @client&.closed?
        @lock.synchronize { @client.connect if @client.closed? }
      end
    end
  end
end
