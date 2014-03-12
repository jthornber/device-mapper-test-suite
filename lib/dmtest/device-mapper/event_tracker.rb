module DM
  class DMEventTracker
    attr_reader :event_nr, :device

    def initialize(n, d)
      @event_nr = n
      @device = d
    end

    # Wait for an event _since_ this one.  Updates event nr to reflect
    # the new number.
    def wait(*args, &condition)
      until condition.call(*args)
        @event_nr = @device.wait(@event_nr)
      end
    end
  end
end
