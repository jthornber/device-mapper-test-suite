require 'thread'

#----------------------------------------------------------------

class ThreadedJobs
  def initialize
    @stop_requested = false
    @lock = Mutex.new
    @tids = Array.new
  end

  def add_job(count, *args, &block)
    count.times do
      @tids << Thread.new(*args) do |*args|
        until @lock.synchronize {@stop_requested} do
          block.call(*args)
        end
      end
    end
  end

  def stop
    @lock.synchronize do
      @stop_requested = true
    end

    @tids.each do |tid|
      tid.join
    end
  end
end

#----------------------------------------------------------------
