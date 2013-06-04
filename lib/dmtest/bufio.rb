class BufIOParams
  def initialize
  end

  def param_file(name)
    "/sys/module/dm_bufio/parameters/#{name}"
  end

  def get_param(name)
    line = ''
    File.open(param_file(name), 'r') do |file|
      line = file.gets
    end

    line.chomp.to_i
  end

  def set_param(name, value)
    File.open(param_file(name), 'w') do |file|
      file.puts(value.to_s)
    end
  end
end
