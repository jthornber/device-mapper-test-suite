require 'dmtest/device_mapper'
require 'dmtest/dataset'
require 'dmtest/fs'
require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/utils'
require 'dmtest/thinp-test'
require 'dmtest/disk-units'
require 'dmtest/utils'
require 'dmtest/test-utils'

#----------------------------------------------------------------

class StripesOnThinStack
  include DM
  include DMThinUtils
  include Utils

  def initialize(dm, data_dev, metadata_dev, nr_stripes, chunk_size, stripe_width)
    @dm = dm
    @data_dev = data_dev
    @metadata_dev = metadata_dev
    @nr_stripes = nr_stripes
    @chunk_size = chunk_size
    @stripe_width = stripe_width
  end

  # FIXME: use a pool stack
  def activate(&block)
    pool_table = Table.new(ThinPoolTarget.new(dev_size(@data_dev),
                                              @metadata_dev,
                                              @data_dev,
                                              512,
                                              8,
                                              true,
                                              true,
                                              false))
    # format the metadata dev
    wipe_device(@metadata_dev, 8)

    with_dev(pool_table) do |pool|
      ids = (0..(@nr_stripes - 1)).to_a
      with_new_thins(pool, @stripe_width, *ids) do |*stripes|
        stripe_pairs = stripes.map {|dev| [dev, 0]}
        stripe_table = Table.new(StripeTarget.new(@stripe_width * @nr_stripes,
                                                  @nr_stripes,
                                                  @chunk_size,
                                                  stripe_pairs))
        with_dev(stripe_table, &block)
      end
    end
  end
end

#----------------------------------------------------------------

class PoolOnStripedStack
  include DM
  include DMThinUtils
  include TinyVolumeManager
  include Utils

  def initialize(dm, data_dev, metadata_dev, nr_stripes, chunk_size)
    @dm = dm
    @data_dev = data_dev
    @metadata_dev = metadata_dev
    @nr_stripes = nr_stripes
    @chunk_size = chunk_size
  end

  def activate(&block)
    tvm = TinyVolumeManager::VM.new
    data_size = dev_size(@data_dev)
    tvm.add_allocation_volume(@data_dev, 0, data_size)

    stripe_width = data_size / @nr_stripes

    # stripe_width * nr_stripes must be a multiple of the chunk size
    stripe_width = round(stripe_width, @chunk_size)

    stripe_range = 0..(@nr_stripes - 1)
      stripe_range.each do |n|
      tvm.add_volume(linear_vol(stripe_name(n), stripe_width))
    end

    tables = stripe_range.map {|n| tvm.table(stripe_name(n))}
    with_devs(*tables) do |*stripes|
      stripe_pairs = stripes.map {|dev| [dev, 0]}
      stripe_table = Table.new(StripeTarget.new(stripe_width * @nr_stripes,
                                                @nr_stripes,
                                                @chunk_size,
                                                stripe_pairs))
      with_dev(stripe_table) do |striped|
        wipe_device(@metadata_dev, 8)
        pool_table = Table.new(ThinPoolTarget.new(dev_size(striped),
                                                  @metadata_dev,
                                                  striped,
                                                  128,
                                                  0,
                                                  true,
                                                  true,
                                                  false))
        with_dev(pool_table, &block)
      end
    end
  end

  private
  def stripe_name(n)
    "stripe_#{n}"
  end

  def round(n, factor)
    (n / factor) * factor
  end
end

#----------------------------------------------------------------

class StripedTests < ThinpTestCase
  include Utils
  include DiskUnits
  extend TestUtils

  def format_and_check(dev, fs_type)
    fs = FS::file_system(fs_type, dev)
    fs.format
    fs.with_mount("./striped_mount") {} # forces a fsck
  end

  def striped_on_thin(nr_stripes, fs_type)
    stack = StripesOnThinStack.new(@dm, @data_dev, @metadata_dev, nr_stripes, 512, gig(10))
    stack.activate {|striped| format_and_check(striped, fs_type)}
  end

  define_tests_across(:striped_on_thin, 2..5, [:ext4, :xfs])

  def thin_on_striped(nr_stripes, fs_type)
    stack = PoolOnStripedStack.new(@dm, @data_dev, @metadata_dev, nr_stripes, 512)
    stack.activate do |pool|
      with_new_thin(pool, gig(10), 0) do |thin|
        format_and_check(thin, fs_type)
      end
    end
  end

  define_tests_across(:thin_on_striped, 2..5, [:ext4, :xfs])
end

#----------------------------------------------------------------
