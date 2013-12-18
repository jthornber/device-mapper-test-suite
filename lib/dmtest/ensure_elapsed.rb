#----------------------------------------------------------------

module EnsureElapsed
  # udev sometimes dives in and holds a device open whilst we're
  # trying to remove it.  This is only a problem when we don't do much
  # with an activated stack.  This method calls a block, ensuring a
  # certain amount of time elapses before it completes.
  def ensure_elapsed_time(seconds, *args, &block)
    t = Thread.new(seconds) do |seconds|
      sleep seconds
    end

    r = block.call(*args)

    t.join
    r
  end
end

#----------------------------------------------------------------
