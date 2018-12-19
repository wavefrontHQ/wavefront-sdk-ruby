# An atomic, thread-safe incrementing counter.
#
# @author Yogesh Prasad Kurmi (ykurmi@vmware.com)

class AtomicInteger
  attr_accessor :value, :lock
  def initialize
    @value = 0
    @lock = Mutex.new
  end

  def increment(num=1)
    lock.synchronize do
      @value += num
    end
  end
end