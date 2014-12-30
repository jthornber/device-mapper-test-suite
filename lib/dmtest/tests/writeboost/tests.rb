require 'dmtest/config'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/pattern_stomper'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tests/cache/fio_subvolume_scenario'

require 'dmtest/tests/writeboost/status'
require 'dmtest/tests/writeboost/stack'

require 'rspec/expectations'
require 'pp'

#----------------------------------------------------------------

module WriteboostTests
  include GitExtract
  include Tags
  include Utils
  include DiskUnits
  include FioSubVolumeScenario
  extend TestUtils

  attr_accessor :stack_maker

  RUBY = 'ruby-2.1.1.tar.gz'
  RUBY_LOCATION = "http://cache.ruby-lang.org/pub/ruby/2.1/ruby-2.1.1.tar.gz"

  def debug_scale?
    $test_scale == :debug
  end

  def grab_ruby
    unless File.exist?(RUBY)
      STDERR.puts "grabbing ruby archive from web"
      system("curl #{RUBY_LOCATION} -o #{RUBY}")
    end
  end

  def build_and_test_ruby
    ProcessControl.run("./configure")
    ProcessControl.run("make -j")

    # page caches are dropped before make test
    ProcessControl.run("echo 3 > /proc/sys/vm/drop_caches")
    ProcessControl.run("make test")
  end

  #--------------------------------

  def test_fio_sub_volume
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev);
    s.activate(true) do
      wait = lambda {sleep(5)}
      fio_sub_volume_scenario(s.wb, &wait)
    end
  end

  def test_fio_cache
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev);
    s.activate(true) do
      do_fio(s.wb, :ext4)
    end
  end

  def test_fio_database_funtime
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev);
    s.activate(true) do
      do_fio(s.wb, :ext4,
             :outfile => AP("fio_writeboost.out"),
             :cfgfile => LP("tests/cache/database-funtime.fio"))
    end
  end

  # really a compound test
  def test_compile_ruby
    grab_ruby

    s = @stack_maker.new(@dm, @data_dev, @metadata_dev);
    s.activate_support_devs() do
      s.cleanup_cache

      ruby = "ruby-2.1.1"
      mount_dir = "./ruby_mount_1"

      # for testing segment size order < 10
      # to dig up codes that depend on the order is 10
      sso = 9

      # (1) first extracts the archive in the directory
      # no writeback - all dirty data is on the cache device
      no_writeback_args = {
        :segment_size_order => sso,
        :enable_writeback_modulator => 0,
        :allow_writeback => 0
      }
      s.table_extra_args = no_writeback_args
      s.activate_top_level(true) do
        fs = FS::file_system(:xfs, s.wb)
        fs.format
        fs.with_mount(mount_dir) do
          pn = RUBY
          ProcessControl.run("cp #{pn} #{mount_dir}")
          Dir.chdir(mount_dir) do
            ProcessControl.run("tar xvfz #{ruby}.tar.gz")
          end
        end
      end

      yes_writeback_args = {
        :segment_size_order => sso,
        :enable_writeback_modulator => 1,
        :allow_writeback => 0,
        :read_cache_threshold => 31
      }
      s.table_extra_args = yes_writeback_args
      # (2) replays the log on the cache device
      # if the data corrupts, Ruby can't compile
      # or fs corrupts.
      s.activate_top_level(true) do
        fs = FS::file_system(:xfs, s.wb)

        # (3) drop all the dirty caches
        # to see writeback works
        s.drop_caches
        fs.with_mount(mount_dir) do
          Dir.chdir("#{mount_dir}/#{ruby}") do
            build_and_test_ruby
          end
        end
      end
    end
  end

  # Reading from RAM buffer is really an unlikely path
  # in real-world workload.
  def test_rambuf_read_fullsize
    # Cache is bigger than backing.
    # So, no overwrite on cache device occurs.
    # Overwrite may writes back caches on the RAM buffer
    # which we attempt to hit on read.
    opts = {
      :backing_sz => meg(16),
      :cache_sz => meg(32),
    }
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev, opts)
    s.activate_support_devs() do
      s.cleanup_cache
      args = {
        :segment_size_order => 10,
        :enable_writeback_modulator => 0,
        :allow_writeback => 0,
      }
      s.table_extra_args = args
      s.activate_top_level(true) do
        st1 = WriteboostStatus.from_raw_status(s.wb.status)
        ps = PatternStomper.new(s.wb.path, k(31), :needs_zero => true)
        ps.stamp(20)
        ps.verify(0, 1)
        st2 = WriteboostStatus.from_raw_status(s.wb.status)
        st2.stat(0, 1, 1, 1).should > st1.stat(0, 1, 1, 1)
      end
    end
  end

  def test_do_dbench
    def run_dbench(s, option)
      s.activate_top_level(true) do
        fs = FS::file_system(:xfs, s.wb)
        fs.format
        mount_dir = "./dbench_wb"
        fs.with_mount(mount_dir) do
          Dir.chdir(mount_dir) do
            system "dbench #{option}"
            ProcessControl.run("sync")
            drop_caches
            s.drop_caches
          end
        end
      end
    end
    @param[0] = debug_scale? ? 1 : 300
    opts = {
      :backing_sz => gig(2),
      :cache_sz => meg(64),
    }
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev, opts)
    s.activate_support_devs do
      s.cleanup_cache
      args = {
        :enable_writeback_modulator => 1,
        :read_cache_threshold => 31, # read-caching enabled
      }
      s.table_extra_args = args
      t = @param[0]
      run_dbench(s, "-t #{t} 4")
      run_dbench(s, "-S -t #{t} 4") # -S: Directory operations are SYNC
      run_dbench(s, "-s -t #{t} 4") # -s: All operations are SYNC
    end
  end

  def test_do_stress
    @param[0] = debug_scale? ? 1 : 60
    opts = {
      :cache_sz => meg(128),
    }
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev, opts)
    s.activate_support_devs() do
      s.cleanup_cache
      s.activate_top_level(true) do
        fs = FS::file_system(:xfs, s.wb)
        fs.format
        mount_dir = "./mnt_wb"
        fs.with_mount(mount_dir) do
          Dir.chdir(mount_dir) do
            ProcessControl.run("stress -v --timeout #{@param[0]}s --hdd 4 --hdd-bytes 512M")
          end
        end
      end
    end
  end

  # Writeboost always split I/O to 4KB fragment.
  # This actually deteriorates direct reads from the backing device.
  # This test is to see how Writeboost deteriorates the block reads compared to backing device only.
  def test_fio_read_overhead
    @param[0] = debug_scale? ? 1 : 128

    def run_fio(dev, iosize)
      ProcessControl.run("fio --name=test --filename=#{dev.path} --rw=randread --ioengine=libaio --direct=1 --size=#{@param[0]}m --ba=#{iosize}k --bs=#{iosize}k --iodepth=32")
      ProcessControl.run("sync")
      drop_caches
    end

    s = @stack_maker.new(@dm, @data_dev, @metadata_dev)
    s.activate_support_devs do
      s.cleanup_cache
      [1, 2, 4, 8, 16, 32, 64, 128].each do |iosize|
        s.activate_top_level(true) do
          report_time("iosize=#{iosize}k", STDERR) do
            run_fio(s.wb, iosize)
          end
        end
      end
    end
  end

  # Test to see the effect of splitting by seqread
  def test_split_overhead
    def run_dd(dev, iosize)
      system("dd if=#{dev.path} iflag=direct of=/dev/null bs=#{iosize}")
    end
    opts = {
      :backing_sz => gig(2),
    }
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev, opts)
    s.activate_support_devs do
      s.cleanup_cache
      ["4K", "512K", "64M"].each do |iosize|
        s.activate_top_level(true) do
          report_time("iosize=#{iosize}", STDERR) do
            run_dd(s.wb, iosize)
          end
        end
      end
    end
  end

  # This test aims to pass unlikely path in invalidate_prev_cache()
  def test_invalidate_prev_cache
    @param[0] = debug_scale? ? 3 : 30
    opts = {
      # The 127th writes incurs queue_current_buffer().
      # Others run into unfavorable path to write back the preivous cache on cache device.
      :backing_sz => 1 * (128 - 1) * k(4),
      :cache_sz => meg(1) + 3 * 128 * k(4), # 1M (super block) + 3 segments
    }
    # 512B stride write repeats in 30sec.
    # The offset increases by 4k (E.g. 0, 4096, 8192, ...)
    def run_fio(dev)
      system("fio --name=test --time_based --runtime=#{@param[0]} --filename=#{dev.path} --rw=write:3584 --ioengine=libaio --direct=1 --bs=512")
    end
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev, opts)
    s.activate_support_devs do
      s.cleanup_cache
      # Stop automated writeback
      s.table_extra_args = {
        :segment_size_order => 10,
        :enable_writeback_modulator => 0,
        :allow_writeback => 0,
        :nr_max_batched_writeback => 1,
      }
      s.activate_top_level(true) do
        report_time("", STDERR) do
          run_fio(s.wb)
        end
        # All writes except the first few handreds result in write hit on the cache device
        # which leads to unfavorable foreground writeback. To see the stat, uncomment this line.
        # print WriteboostStatus.from_raw_status(s.wb.status).format_stat_table
      end
    end
  end

  # This test shows how badly Writeboost performs with all-sync writes.
  def test_sync_writes
    @param[0] = debug_scale? ? 1 : 4
    def run(s)
      s.table_extra_args = {
        :enable_writeback_modulator => 1,
      }
      s.cleanup_cache
      s.activate_top_level(true) do
        fs = FS::file_system(:xfs, s.wb)
        fs.format
        dir = "./fio_test"
        fs.with_mount(dir) do
          report_time("", STDERR) do
            Dir.chdir(dir) do
              # Alway submit barriers per one 512B write
              # Note: --write_barrier and --io_limit is not available in fio v2.0.8
              ProcessControl.run("fio --name=test --filename=#{s.wb.path} --rw=randwrite --ioengine=libaio --direct=1 --fsync=1 --write_barrier=1 --io_limit=#{@param[0]}M --bs=512")
            end
            ProcessControl.run("sync")
            drop_caches
            s.drop_caches # Wait until all cache blocks becomes clean.
          end
        end
      end
    end
    opts = {
      :cache_sz => meg(2) # The cache device is very small.
    }
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev, opts)
    s.activate_support_devs do
      run(s)
    end
  end

  def test_no_read_cache
    def run(dev)
      # seqread with 4K holes
      system("fio --name=test --filename=#{dev.path} --io_limit=16M --rw=read:4K --bs=4K --direct=1")
    end
    opts = {
      :cache_sz => meg(32)
    }
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev, opts)
    s.activate_support_devs do
      s.cleanup_cache
      s.activate_top_level(true) do
        run(s.wb)
        st1 = WriteboostStatus.from_raw_status(s.wb.status)
        run(s.wb)
        st2 = WriteboostStatus.from_raw_status(s.wb.status)
        st2.stat(0, 1, 0, 1).should == st1.stat(0, 1, 0, 1)
      end
    end
  end

  def test_read_cache
    def run(dev)
      system("fio --name=test --filename=#{dev.path} --io_limit=16M --rw=read:4K --bs=4K --direct=1")
    end
    opts = {
      :cache_sz => meg(32)
    }
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev, opts)
    s.activate_support_devs do
      s.cleanup_cache
      s.table_extra_args = {
        :read_cache_threshold => 1,
      }
      st1 = nil
      st2 = nil
      s.activate_top_level(true) do
        run(s.wb)
        st1 = WriteboostStatus.from_raw_status(s.wb.status)
      end
      s.activate_top_level(true) do
        run(s.wb)
        st2 = WriteboostStatus.from_raw_status(s.wb.status)
      end
      st2.stat(0, 1, 0, 1).should > st1.stat(0, 1, 0, 1)
    end
  end

  def test_read_cache_threshold
    def run(dev)
    end
    opts = {
      :backing_sz => gig(2),
    }
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev, opts)
    s.activate_support_devs do
      s.cleanup_cache
      s.table_extra_args = {
        :read_cache_threshold => 127,
      }
      s.activate_top_level(true) do
        system("dd if=#{s.wb.path} iflag=direct of=/dev/null bs=1M count=1000 &
                dd if=#{s.wb.path} iflag=direct of=/dev/null bs=1M skip=500 count=1000 &
                wait")
        st1 = WriteboostStatus.from_raw_status(s.wb.status)
        system("dd if=#{s.wb.path} iflag=direct of=/dev/null bs=1M count=1000")
        st2 = WriteboostStatus.from_raw_status(s.wb.status)
        st2.stat(0, 1, 0, 1).should == st1.stat(0, 1, 0, 1)
      end
    end
  end

  #--------------------------------

  def test_wipe_device
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev,
                         :backing_sz => meg(1024),
                         :cache_sz => gig(3))
    s.activate_support_devs do
      s.cleanup_cache
      s.table_extra_args = {
        :enable_writeback_modulator => 1,
        :allow_writeback => 1
      }

      s.activate_top_level(true) do
        report_time("wiping device", STDERR) do
          wipe_device(s.wb)
        end
      end
    end
  end

  def test_wipe_device_small_blocks
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev,
                         :backing_sz => meg(1024),
                         :cache_sz => gig(3))
    s.activate_support_devs do
      s.cleanup_cache
      s.table_extra_args = {
        :enable_writeback_modulator => 1,
        :allow_writeback => 1
      }

      s.activate_top_level(true) do
        report_time("wiping device", STDERR) do
          ProcessControl.run("dd if=/dev/zero of=#{s.wb} bs=4096 count=#{dev_size(s.wb) / 8}")
        end
      end
    end
  end

  def test_wipe_device_tiny_blocks
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev,
                         :backing_sz => meg(1024),
                         :cache_sz => gig(3))
    s.activate_support_devs do
      s.cleanup_cache
      s.table_extra_args = {
        :enable_writeback_modulator => 1,
        :allow_writeback => 1
      }

      s.activate_top_level(true) do
        report_time("wiping device", STDERR) do
          ProcessControl.run("dd if=/dev/zero of=#{s.wb} bs=512 count=#{dev_size(s.wb)}")
        end
      end
    end
  end

  def test_git_extract_cache_quick
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev,
                         :backing_sz => gig(2),
                         :cache_sz => meg(1024))
    s.activate_support_devs do
      s.cleanup_cache
      s.table_extra_args = {
        :enable_writeback_modulator => 1,
        :allow_writeback => 1
      }

      s.activate_top_level(true) do
        git_prepare(s.wb, :ext4)
        git_extract(s.wb, :ext4, TAGS[0..5])
      end
    end
  end

  # Writeboost sorts in writeback.
  # This test is to see how the sorting takes effects.
  # Aspects
  # - Does just stacking writeboost can always boost write.
  # - How the effect changes according to the nr_max_batched_writeback tunable?
  def test_writeback_sorting_effect
    @param[0] = debug_scale? ? 1 : 128
    def run_wb(s, batch_size)
      s.cleanup_cache
      s.table_extra_args = {
        :nr_max_batched_writeback => batch_size,
      }
      s.activate_top_level(true) do
        fs = FS::file_system(:xfs, s.wb)
        fs.format
        dir = "./fio_test"
        fs.with_mount(dir) do
          report_time("batch_size(#{batch_size})", STDERR) do
            Dir.chdir(dir) do
              ProcessControl.run("fio --name=test --rw=randwrite --ioengine=libaio --direct=1 --size=#{@param[0]}m --bs=4k --ba=4k --iodepth=32")
            end
            ProcessControl.run("sync")
            drop_caches
            # For Writeboost,
            # we wait for all the dirty blocks are written back to the backing device.
            # The data written back are all persistent.
            s.drop_caches
          end
        end
      end
    end

    s = @stack_maker.new(@dm, @data_dev, @metadata_dev, :cache_sz => meg(129))
    s.activate_support_devs do
      [4, 32, 128, 256].each do |batch_size|
        run_wb(s, batch_size)
      end
    end
  end

  # 4KB randwrite performance
  def test_fio_randwrite_perf
    @param[0] = debug_scale? ? 1 : 500
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev, :cache_sz => meg(@param[0] + 100))
    s.activate_support_devs do
      s.cleanup_cache
      # Migration is off
      s.table_extra_args = {
        :enable_writeback_modulator => 0,
        :allow_writeback => 0
      }
      s.activate_top_level(true) do
        system "fio --name=test --filename=#{s.wb.path} --rw=randwrite --ioengine=libaio --direct=1 --size=#{@param[0]}m --ba=4k --bs=4k --iodepth=32"
      end
    end
  end
  def test_fio_cache_seqwrite # Baseline
    @param[0] = debug_scale? ? 1 : 500
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev, :cache_sz => meg(@param[0] + 100))
    s.activate_support_devs do
      system "fio --name=test --filename=#{s.cache_dev.path} --rw=write --ioengine=libaio --direct=1 --size=#{@param[0]}m --bs=256k --iodepth=32"
    end
  end
end

class WriteboostTestsBackingDevice < ThinpTestCase
  include WriteboostTests

  def setup
    super
    @stack_maker = WriteboostStackBackingDevice
    @param = []
  end
end

class WriteboostTestsType0 < ThinpTestCase
  include WriteboostTests

  def setup
    super
    @stack_maker = WriteboostStackType0
    @param = []
  end
end

class WriteboostTestsType1 < ThinpTestCase
  include WriteboostTests

  def setup
    super
    @stack_maker = WriteboostStackType1
    @param = []
  end
end

#----------------------------------------------------------------
