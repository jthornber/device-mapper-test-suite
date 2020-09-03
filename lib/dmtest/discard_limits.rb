require 'pathname'

class DiscardLimits
  attr_reader :dev, :supported, :granularity, :max_bytes

  def initialize(dev)
    @dev = Pathname.new(dev).realpath.basename
    @granularity = read_param(:granularity)
    @max_bytes = read_param(:max_bytes)
    @supported = @max_bytes > 0
  end

  private

  def read_param(p)
    disk = dev.to_s
    type = `lsblk -n /dev/#{disk} | grep -w #{disk} | sed 's/[ \t]*$//; s/.*[ \t]//'`.strip
    if type == "part"
      disk = `basename $(dirname $(find /sys -type d -name #{disk}))`.strip
    end
    line = ''
    File.open("/sys/block/#{disk}/queue/discard_#{p}", 'r') do |file|
      line = file.gets
    end

    line.chomp.to_i
  end
end
