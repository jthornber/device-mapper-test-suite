require 'dmtest/blktrace'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/thinp-test'

#----------------------------------------------------------------

class ToolsTests < ThinpTestCase
  include GitExtract
  include Utils
  include BlkTrace
  include TinyVolumeManager
  extend TestUtils

  def setup
    super
  end

  def forbidden_on_live_metadata(cmd)
    s = CacheStack.new(@dm, @metadata_dev, @data_dev,
                       :format => true,
                       :block_size => k(32),
                       :cache_size => meg(512),
                       :data_size => gig(4),
                       :policy => Policy.new('smq', :migration_threshold => 1024))
    s.activate do
      assert_raises(ProcessControl::ExitError) do
        ProcessControl.run(cmd)
      end
    end
  end

  def forbidden_on_live_data(cmd)
    with_standard_linear(:data_size => gig(1)) do |linear|
        assert_raises(ProcessControl::ExitError) do
        ProcessControl.run(cmd)
      end
    end
  end

  def allowed_on_live_metadata(cmd)
    s = CacheStack.new(@dm, @metadata_dev, @data_dev,
                       :format => true,
                       :block_size => k(32),
                       :cache_size => meg(512),
                       :data_size => gig(4),
                       :policy => Policy.new('smq', :migration_threshold => 1024))
    s.activate do
      with_new_thin(pool, @volume_size, 0) do |thin|
        ProcessControl.run(cmd)
      end
    end
  end

  define_test :you_cannot_run_cache_check_on_live_metadata do
    forbidden_on_live_metadata("cache_check #{@metadata_dev}")
  end

  #--------------------------------

  def corrupt_metadata(md)
    ProcessControl::run("dd if=/dev/urandom of=#{md} count=512 seek=4096 bs=1")
  end

  def copy_metadata(md, tmp_file)
    ProcessControl::run("dd if=#{md} of=#{tmp_file}")
  end

  def repair_metadata(md)
    tmp_file = 'metadata.repair.tmp'
    copy_metadata(md, tmp_file)
    ProcessControl::run("cache_repair -i #{tmp_file} -o #{md}")
  end

  def check_metadata(md)
    ProcessControl::run("cache_check #{md}")
  end

  def repair_cycle(md)
    corrupt_metadata(md)
    repair_metadata(md)
    check_metadata(md)
  end

  define_test :cache_repair_repeatable do
    # We want to use a little metadata dev for this since we copy it
    # to a temp file.
    tvm = VM.new
    tvm.add_allocation_volume(@metadata_dev)
    tvm.add_volume(linear_vol('metadata', meg(50)))

    with_dev(tvm.table('metadata')) do |md|
      stack = CacheStack.new(@dm, md, @data_dev,
                             :format => true,
                             :block_size => k(32),
                             :cache_size => meg(20),
                             :data_size => gig(4),
                             :policy => Policy.new('smq', :migration_threshold => 1024))
      stack.activate do
        wipe_device(stack.cache)
      end

      repair_cycle(md)
      repair_cycle(md)
    end
  end

  #--------------------------------

  define_test :cache_offline_writeback do
    s = CacheStack.new(@dm, @metadata_dev, @data_dev,
                       :format => true,
                       :block_size => k(32),
                       :cache_size => meg(512),
                       :data_size => gig(4),
                       :policy => Policy.new('smq', :migration_threshold => 1024))
    s.activate_support_devs do
      s.prepare_populated_cache(:dirty_percentage => 50)

      # FIXME: metadata update doesn't work yet.
      cmd = "cache_writeback --metadata-device #{s.md} --fast-device #{s.ssd} --origin-device #{s.origin} --buffer-size-meg 16 --no-metadata-update"
      STDERR.puts cmd
      ProcessControl.run(cmd)
    end
  end
end

#----------------------------------------------------------------
