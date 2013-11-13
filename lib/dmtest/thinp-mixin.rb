require 'dmtest/benchmarking'
require 'dmtest/bufio'
require 'dmtest/device-mapper/lexical_operators'
require 'dmtest/device_mapper'
require 'dmtest/log'
require 'dmtest/metadata-utils'
require 'dmtest/pool-stack'
require 'dmtest/prerequisites-checker'
require 'dmtest/process'
require 'dmtest/tvm'
require 'dmtest/utils'

#require 'rspec'

#----------------------------------------------------------------

$prereqs = Prerequisites.requirements do
  require_in_path('thin_check',
                  'thin_dump',
                  'thin_restore',
                  'dt',
                  'blktrace',
                  'bonnie++')
  require_ruby_version /^1.9/
end

#------------------------------------------------

module ThinpTestMixin
  include DM
  include DMThinUtils
  include Benchmarking
  include MetadataUtils
  include ProcessControl
  include TinyVolumeManager

  # A little shim to convert to the new config
  def get_config
    p = $profile                # blech
    {
      :metadata_dev => p.metadata_dev,
      :data_dev => p.data_dev
    }
  end

  def setup
    check_prereqs

    config = get_config
    @metadata_dev = config[:metadata_dev]
    @data_dev = config[:data_dev]

    @data_block_size = config.fetch(:data_block_size, 128)

    @size = config.fetch(:data_size, 20971520)
    @size /= @data_block_size
    @size *= @data_block_size

    @volume_size = config.fetch(:volume_size, 2097152)

    @tiny_size = @data_block_size
    @low_water_mark = config.fetch(:low_water_mark, 5)
    @mass_fs_tests_parallel_runs = config.fetch(:mass_fs_tests_parallel_runs, 128)

    @dm = DMInterface.new

    @bufio = BufIOParams.new
    @bufio.set_param('peak_allocated_bytes', 0)

    wipe_device(@metadata_dev, 8)
  end

  def teardown
    info("Peak bufio allocation was #{@bufio.get_param('peak_allocated_bytes')}")
  end

  def limit_metadata_dev_size(size)
    max_size = 8355840
    size = max_size if size > max_size
    size
  end

  #--------------------------------

  # table generation
  def standard_pool_table(size, opts = Hash.new)
    opts[:data_size] = size
    opts[:low_water_mark] = @low_water_mark
    opts[:block_size] = @data_block_size
    stack = PoolStack.new(@dm, @data_dev, @metadata_dev, opts)
    stack.pool_table
  end

  def custom_data_pool_table(data_dev, size, opts = Hash.new)
    opts[:data_size] = size
    opts[:low_water_mark] = @low_water_mark
    opts[:block_size] = @data_block_size
    stack = PoolStack.new(@dm, data_dev, opts)
    stack.pool_table
  end

  def standard_linear_table(opts = Hash.new)
    data_size = opts.fetch(:data_size, dev_size(@data_dev))
    Table.new(LinearTarget.new(data_size, @data_dev, 0))
  end

  def fake_discard_table(opts = Hash.new)
    dev = opts.fetch(:dev, @data_dev)
    offset = opts.fetch(:offset, 0)
    granularity = opts.fetch(:granularity, @data_block_size)
    size = opts.fetch(:size, dev_size(@data_dev) - offset)
    max_discard_sectors = opts.fetch(:max_discard_sectors, @data_block_size)
    discard_support = opts.fetch(:discard_support, true)
    discard_zeroes = opts.fetch(:discard_zeroes, false)

    Table.new(FakeDiscardTarget.new(size, dev, offset, granularity, max_discard_sectors,
                                    !discard_support, discard_zeroes))
  end

  #--------------------------------

  def with_standard_pool(size, opts = Hash.new, &block)
    opts[:data_size] = size
    stack = PoolStack.new(@dm, @data_dev, @metadata_dev, opts)
    stack.activate(&block)
  end

  def with_error_pool(size, opts = Hash.new, &block)
    opts[:data_size] = size
    
    error_table = Table.new(ErrorTarget.new(size))
    with_dev(error_table) do |error_dev|
      stack = PoolStack.new(@dm, error_dev, @metadata_dev, opts)
      stack.activate(&block)
    end
  end

  def with_custom_data_pool(data_dev, size, opts = Hash.new, &block)
    opts[:data_size] = size
    stack = PoolStack.new(@dm, data_dev, @metadata_dev, opts)
    stack.activate(&block)
  end

  def with_standard_linear(opts = Hash.new, &block)
    with_dev(standard_linear_table(opts), &block)
  end

  def with_fake_discard(opts = Hash.new, &block)
    with_dev(fake_discard_table(opts), &block)
  end

  def with_new_snap(pool, size, id, origin, thin = nil, &block)
    if thin.nil?
        pool.message(0, "create_snap #{id} #{origin}")
        with_thin(pool, size, id, &block)
    else
      thin.pause do
        pool.message(0, "create_snap #{id} #{origin}")
      end
      with_thin(pool, size, id, &block)
    end
  end

  def in_parallel(*ary, &block)
    threads = Array.new
    ary.each do |entry|
      threads << Thread.new(entry) do |e|
        block.call(e)
      end
    end

    threads.each {|t| t.join}
  end

  def assert_bad_table(table)
    assert_raise(ExitError) do
      with_dev(table) do |pool|
      end
    end
  end

  def with_mounts(fs, mount_points)
    if fs.length != mount_points.length
      raise "number of filesystems differs from number of mount points"
    end

    mounted = Array.new

    teardown = lambda do
      mounted.each {|fs| fs.umount}
    end

    bracket_(teardown) do
      0.upto(fs.length - 1) do |i|
        fs[i].mount(mount_points[i])
        mounted << fs[i]
      end

      yield
    end
  end

  def count_deferred_ios(&block)
    b = get_deferred_io_count
    block.call
    get_deferred_io_count - b
  end

  def reload_with_error_target(dev)
    dev.pause do
      dev.load(Table.new(ErrorTarget.new(dev.active_table.size)))
    end
  end

  private
  def get_deferred_io_count
    ProcessControl.run("cat /sys/module/dm_thin_pool/parameters/deferred_io_count").to_i
  end

  def check_prereqs
    begin
      # FIXME: put back
      #$prereqs.check
    rescue => e
      STDERR.puts e
      STDERR.puts "Missing prerequisites, please see the README"
      exit(1)
    end
  end
end

#----------------------------------------------------------------
