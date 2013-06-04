require 'dmtest/process'
require 'dmtest/math-utils'
require 'tempfile'

# A hodge podge of functions that should probably find a better home.
module Utils
  include MathUtils

  def dev_size(dev_or_path)
    ProcessControl.system("102400", "blockdev --getsz #{dev_or_path}").chomp.to_i
  end

  def dev_logical_block_size(dev_or_path)
    ProcessControl.system("102400", "blockdev --getbsz #{dev_or_path}").chomp.to_i
  end

  def _dd_device(ifile, ofile, oflag, sectors)
    # quick hack
    if ofile == '/dev/null'
      size = dev_size(ifile)
    else
      size = dev_size(ofile)
    end

    sectors = size if sectors.nil? || size < sectors

    # in case we got many sectors, do dd in large blocks
    block_size = 64 * 1024 * 2 # 64M in sectors
    count = sectors / block_size

    if count > 0
      ProcessControl.run("dd if=#{ifile} of=#{ofile} #{oflag} bs=#{block_size * 512} count=#{count}")
    end

    # do we have a partial dd block to do at the end?
    remainder = sectors % block_size
    if remainder > 0
      # deliberately missing out #{oflag} because we don't want O_DIRECT
      ProcessControl.run("dd if=#{ifile} of=#{ofile} bs=512 count=#{remainder} seek=#{count * block_size}")
    end
  end

  def wipe_device(dev_or_path, sectors = nil)
    _dd_device("/dev/zero", dev_or_path, "oflag=direct", sectors)
  end

  def read_device_to_null(dev_or_path, sectors = nil)
    _dd_device(dev_or_path, "/dev/null", "", sectors)
  end

  # Runs dt on the device, defaulting to random io and the 'iot'
  # pattern.
  def dt_device(file, io_type = nil, pattern = nil, size = nil)
    iotype = io_type.nil? ? "random" : "sequential"
    pattern = "iot" if pattern.nil?
    size = dev_size(file) if size.nil?

    ProcessControl.run("dt of=#{file} capacity=#{size*512} pattern=#{pattern} passes=1 iotype=#{iotype} bs=4M rseed=1234")
  end

  def verify_device(ifile, ofile)
    iotype = 'random'
    pattern = "iot"
    size = dev_size(ifile)

    ProcessControl.run("dt iomode=verify if=#{ifile} of=#{ofile} bs=4M rseed=1234")
  end

  def get_dev_code(path)
    stat = File.stat(path)
    if stat.blockdev?
      "#{stat.rdev_major}:#{stat.rdev_minor}"
    else
      path
    end
  end

  def Utils.with_temp_file(name)
    f = Tempfile.new(name)
    begin
      yield(f)
    ensure
      f.close
      f.unlink
    end
  end

  def Utils.retry_if_fails(duration)
    begin
      yield
    rescue Exception
      ProcessControl.sleep(duration)
      yield
    end
  end

  def _ten_to_str(num_to_str, n)
    r = []

    if (n <= 20)
      r << num_to_str[n] + " "
    else
      ten = n / 10 * 10
      one = n - ten
      r << num_to_str[one] + " " if one > 0
      r << num_to_str[ten] + " "
    end

    r.reverse
  end

  def number_to_string(v)
    mill = 0
    r = []
    # Hash mapping from numbers to respective word. eg. 1000000 => 'million'
    num_to_str = {}
    %w|zero one two three four five six seven eight nine ten eleven
       twelve thirteen fourteen fifteen sixteen seventeen eighteen
       nineteen|.each_with_index { |word, i| num_to_str[i] = word }
    %w|zero ten twenty thirty forty fifty sixty seventy eighty
       ninety hundred |.each_with_index { |word, i| num_to_str[i*10] = word }
    %w|one thousand million billion trillion|.each_with_index { |word, i| num_to_str[10**(i*3)] = word }

    while v > 0
      tenth = (" " + v.to_s)[-2..-1].to_i
      hundreds = ("  " + v.to_s)[-3..-3].to_i
      r << num_to_str[10 ** (mill * 3)] + " " if mill > 0 && tenth + hundreds > 0
      r << _ten_to_str(num_to_str, tenth) if tenth > 0
      ( r << num_to_str[100] + " "; r << num_to_str[hundreds] + " ") if hundreds > 0
      v /= 1000
      mill += 1
    end

    r.reverse.to_s.chop
  end

end
