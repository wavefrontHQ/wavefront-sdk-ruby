# Connection Handler class for sending data to a Wavefront proxy.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)

require 'socket'

require_relative 'atomic_integer'

# Connection Handler.
# For sending data to a Wavefront proxy listening on a given port.
module Wavefront
  class ProxyConnectionHandler
    # Construct ProxyConnectionHandler.
    # @param address [String] Proxy Address
    # @param port [Integer] Proxy Port
    def initialize(address, port)
      @failures = AtomicInteger.new
      @address = address
      @port = port
      @reconnecting_socket = nil
      @lock = Mutex.new
    end

    # Open a socket connection to the given address:port
    def connect
      @lock.synchronize do
        @reconnecting_socket = TCPSocket.open(@address, @port)
      end
    end

    # Close socket if it's open now.
    def close
      @reconnecting_socket.close if @reconnecting_socket
    end

    # Returns number of failures
    def failure_count
      @failures.value
    end

    # Increment failure count
    def increment_failure_count
      @failures.increment
    end

    # Send data via proxy.

    # @param line_data [String] Data to be sent
    # @param reconnect [Boolean] If it's the second time trying to send data
    def send_data(line_data, reconnect=true)
      begin
        connect unless @reconnecting_socket
        @reconnecting_socket.puts(line_data.encode('utf-8'))
      rescue SocketError => error
        if reconnect
          @reconnecting_socket = nil
          # Try to resend
          send_data(line_data, false)
        else
          # Second time trying failed
          raise error
        end
      end
    end
  end
end