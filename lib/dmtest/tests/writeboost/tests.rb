require 'dmtest/config'
require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tests/cache/fio_subvolume_scenario'

require 'dmtest/tests/writeboost/stack'

require 'pp'

#----------------------------------------------------------------

class WriteboostTests < ThinpTestCase
  include GitExtract
  include Tags
  include Utils
  include DiskUnits
  include FioSubVolumeScenario
  extend TestUtils

  attr_accessor :stack_maker

  def test_fio_sub_volume
    return unless @stack_maker
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev);
    s.activate(true) do
      s.cleanup_cache
      wait = lambda {sleep(5)}
      fio_sub_volume_scenario(s.wb, &wait)
    end
  end

  def test_fio_cache
    return unless @stack_maker
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev);
    s.activate(true) do
      s.cleanup_cache
      do_fio(s.wb, :ext4)
    end
  end

  def test_fio_database_funtime
    return unless @stack_maker
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev);
    s.activate(true) do
      s.cleanup_cache
      do_fio(s.wb, :ext4,
             :outfile => AP("fio_writeboost.out"),
             :cfgfile => LP("tests/cache/database-funtime.fio"))
    end
  end

  # really a compound test
  def test_compile_ruby
    def build_and_test_ruby
      ProcessControl.run("./configure")
      ProcessControl.run("make -j")
      # page caches are dropped before make test
      ProcessControl.run("echo 3 > /proc/sys/vm/drop_caches")
      ProcessControl.run("make test")
    end

    return unless @stack_maker
    s = @stack_maker.new(@dm, @data_dev, @metadata_dev);
    s.activate_support_devs() do
      s.cleanup_cache

      ruby = "ruby-2.1.1"
      mount_dir = "./ruby_mount_1"

      # for testing segment size order < 10
      # to dig up codes that depend on the order is 10
      sso = 9

      # (1) first extracts the archive in the directory
      # no migration - all dirty data is on the cache device
      no_migrate_opts = {
        :segment_size_order => sso,
        :enable_migration_modulator => 0,
        :allow_migrate => 0
      }
      s.opts = no_migrate_opts
      s.activate_top_level(true) do
        fs = FS::file_system(:xfs, s.wb)
        fs.format
        fs.with_mount(mount_dir) do
          pn = LP("tests/writeboost/#{ruby}.tar.gz")
          ProcessControl.run("cp #{pn} #{mount_dir}")
          Dir.chdir(mount_dir) do
            ProcessControl.run("tar xvfz #{ruby}.tar.gz")
          end
        end
      end

      yes_migrate_opts = {
        :segment_size_order => sso,
        :enable_migration_modulator => 1,
        :allow_migrate => 0
      }
      s.opts = yes_migrate_opts
      # (2) replays the log on the cache device
      # if the data corrupts, Ruby can't compile
      # or fs corrupts.
      s.activate_top_level(true) do
        fs = FS::file_system(:xfs, s.wb)

        # (3) drop all the dirty caches
        # to see migration works
        s.wb.message(0, "drop_caches")
        fs.with_mount(mount_dir) do
          Dir.chdir("#{mount_dir}/#{ruby}") do
            build_and_test_ruby
          end
        end
      end
    end
  end
end

class WriteboostTestsType0 < WriteboostTests
  def setup
    super
    @stack_maker = WriteboostStackType0
  end
end

class WriteboostTestsType1 < WriteboostTests
  def setup
    super
    @stack_maker = WriteboostStackType1
  end
end

#----------------------------------------------------------------
