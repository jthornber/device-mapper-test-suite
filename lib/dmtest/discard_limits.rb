require 'pathname'

class DiscardLimits
  attr_reader :dev, :supported, :granularity, :max_bytes

  def initialize(dev)
    @dev = Pathname.new(dev).basename
    @granularity = read_param(:granularity)
    @max_bytes = read_param(:max_bytes)
    @supported = @max_bytes > 0
  end

  private

  def read_param(p)
    line = ''
    File.open("/sys/block/#{dev.to_s}/queue/discard_#{p}", 'r') do |file|
      line = file.gets
    end

    line.chomp.to_i
  end
end
