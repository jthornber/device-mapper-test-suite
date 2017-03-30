require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/cache_stack'
require 'dmtest/cache_utils'
require 'dmtest/cache_policy'

require 'rspec/expectations'

#----------------------------------------------------------------

class CleanerTests < ThinpTestCase
  include GitExtract
  include Utils
  include DiskUnits
  include CacheUtils
  extend TestUtils

  METADATA_VERSIONS = [1, 2]

  def setup
    super
    @data_block_size = k(32)
    @cache_blocks = 1024
  end

  def std_stack(opts = {})
    std_opts = {
      :data_size => gig(4),
      :cache_size => gig(1),
      :io_mode => :writeback,
      :block_size => k(64),
      :policy => Policy.new(:smq, :migration_threshold => 1024)
    }

    make_stack(std_opts.merge(opts))
  end

  def confirm_clean
    # Passthrough mode doesn't allow any dirty blocks, so is a good
    # way of confirming the cache is clean.
    s = std_stack(:format => false,
                  :io_mode => :passthrough)
    s.activate do      
    end
  end

  #--------------------------------

  def a_fresh_cache_is_trivial_to_clean(version)
    s = std_stack(:metadata_version => version,
                  :policy => Policy.new('cleaner'))
    s.activate do
      wait_for_all_clean(s.cache)
    end

    confirm_clean
  end

  define_tests_across(:a_fresh_cache_is_trivial_to_clean,
                      METADATA_VERSIONS)

  #--------------------------------

  def a_dirtied_cache_can_be_cleaned_recreate(version)
    s = std_stack(:metadata_version => version)
    s.activate do
      git_prepare(s.cache, :ext4)
      git_extract(s.cache, :ext4, TAGS[0..5])
    end

    s = std_stack(:format => false,
                  :metadata_version => version,
                  :policy => Policy.new('cleaner'))
    s.activate do
      # FIXME: are blocks marked clean when their writeback comences rather than completes?
      wait_for_all_clean(s.cache)
    end

    confirm_clean
  end

  define_tests_across(:a_dirtied_cache_can_be_cleaned_recreate,
                      METADATA_VERSIONS)

  #--------------------------------

  # bz 1337588 suggests quickly reloading to passthrough mode leaves
  # dirty blocks
  def a_dirtied_cache_can_be_cleaned_reload(version)
    s = std_stack(:metadata_version => version)
    s.activate do
      git_prepare(s.cache, :ext4)
      git_extract(s.cache, :ext4, TAGS[0..5])

      s.cache.pause do
        s.change_policy(Policy.new('cleaner'))
        s.reload_cache
      end

      wait_for_all_clean(s.cache)

      s.cache.pause do
        s.change_io_mode(:passthrough)
        s.reload_cache
      end
    end
  end

  define_tests_across(:a_dirtied_cache_can_be_cleaned_reload,
                      METADATA_VERSIONS)

  #---------------------------------

  # bz1437251
  # Assumes a VG created and named 'cache_sanity'
  # lvcreate --yes -L 4G -n corigin cache_sanity /dev/sdb1
  # lvcreate --yes -L 4G -n resize cache_sanity /dev/sda1
  # lvcreate --yes -L 12M -n resize_meta cache_sanity /dev/sda1
  # lvconvert --cachemetadataformat 1 --yes --type cache-pool --cachepolicy smq --cachemode writeback -c 64 --poolmetadata cache_sanity/resize_meta cache_sanity/resize
  # lvconvert --yes --type cache --cachepool cache_sanity/resize cache_sanity/corigin
  #
  # mkfs[.xfs|.ext4] /dev/cache_sanity/corigin
  # mount /dev/cache_sanity/corigin /mnt/corigin
  #
  # dd if=/dev/urandom of=/mnt/corigin/ddfile bs=512 count=100  && dd if=/mnt/corigin/ddfile of=/tmp/ddfile bs=512 count=100
  #
  #
  # lvconvert --uncache /dev/cache_sanity/corigin && umount /mnt/corigin
  define_test :uncache do
    s = std_stack(:metadata_version => 1)
    s.activate do
      fs = FS::file_system(:ext4, s.cache)
      fs.format()

      tid = Thread.new(s) do |s|
	fs.with_mount('./kernel_builds', :discard => false) do
	  STDERR.puts "starting io"
	  ProcessControl.run("dd if=/dev/urandom of=./kernel_builds/ddfile bs=512 count=100000")
	  STDERR.puts "io complete"
        end
      end

      sleep 1  # let the io get rolling

      s.cache.pause do
	s.change_policy(Policy.new('cleaner'))
	s.change_io_mode(:writethrough)
	s.reload_cache
      end

      STDERR.puts "waiting for clean"
      wait_for_all_clean(s.cache)

      STDERR.puts "uncaching"
      s.uncache
      STDERR.puts "uncached"

      tid.join
    end
  end
end

#----------------------------------------------------------------
