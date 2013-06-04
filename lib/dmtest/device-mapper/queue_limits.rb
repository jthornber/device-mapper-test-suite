class QueueLimits
  def initialize(dev_name)
    @dev_name = dev_name
  end

  def method_missing(sym, *args)
    super unless(args.size == 0)

    filename = queue_limit_file(sym.to_s)
    super unless File.exist?(filename)

    get_queue_limit(filename)
  end

  private
  def queue_limit_file(name)
    "/sys/block/#{@dev_name}/queue/#{name}"
  end

  def get_queue_limit(filename)
    contents = File.read(filename)
    m = /(\d+)/.match(contents)
    raise "couldn't parse contents of '#{filename}', expected integer" unless m
    m[1].to_i
  end
end
