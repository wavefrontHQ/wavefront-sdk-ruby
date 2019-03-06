# An atomic, thread-safe incrementing counter.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)
module Wavefront
  class AtomicInteger
    attr_reader :value
    def initialize
      @value = 0
      @lock = Mutex.new
    end

    def increment(num=1)
      @lock.synchronize do
        @value += num
      end
    end
  end
end
