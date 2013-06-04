require 'dmtest/log'

#----------------------------------------------------------------

module Benchmarking
  def report_time(desc, *extra_out, &block)
    elapsed = time_block(&block)
    msg = "Elapsed #{elapsed}: #{desc}"
    info msg
    extra_out.each {|stream| stream.puts msg}
  end
  
  #--------------------------------
  
  private
  def time_block
    start_time = Time.now
    yield
    return Time.now - start_time
  end
end

#----------------------------------------------------------------
