require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/cache_stack'
require 'dmtest/cache_policy'
require 'dmtest/tests/cache/fio_subvolume_scenario'

#----------------------------------------------------------------

class FIOTests < ThinpTestCase
  include FioSubVolumeScenario
  include Utils
  include DiskUnits
  extend TestUtils

  POLICY_NAMES = %w(mq smq)

  def setup
    super
    @data_block_size = meg(1)
  end

  def do_fio__(opts)
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      do_fio(stack.cache, :ext4,
             :outfile => AP("fio_dm_cache.out"),
             :cfgfile => LP("tests/cache/database-funtime.fio"))
      pp CacheStatus.new(stack.cache)
    end
  end

  def fio_across_cache_size(policy_name)
    [512, 1024, 2048, 4096, 8192, 8192 + 1024].each do |cache_size|
      report_time("cache size = #{cache_size}, policy = #{policy_name}", STDERR) do
        do_fio__(:policy => Policy.new(policy_name, :migration_threshold => 1024),
                 :cache_size => meg(cache_size),
                 :block_size => k(32),
                 :data_size => gig(16))
      end
    end
  end

  define_tests_across(:fio_across_cache_size, POLICY_NAMES)

  #--------------------------------

  def origin_same_size_as_ssd(policy_name)
    report_time("fio", STDERR) do
      do_fio__(:policy => Policy.new(policy_name, :migration_threshold => 1024),
               :metadata_size => meg(128),
               :cache_size => gig(10),
               :block_size => k(32),
               :data_size => gig(10))
    end
  end

  define_tests_across(:origin_same_size_as_ssd, POLICY_NAMES)

  #---------------------------------

  def run_fio(dev, name)
    outfile = AP("fio-#{name}.out")
    cfgfile = LP("tests/cache/jharrigan.fio")

    fs = FS::file_system(:ext4, dev)
    fs.format(:discard => false)
    fs.with_mount('./fio_test', :discard => false) do
      Dir.chdir('./fio_test') do
	ProcessControl.run("fio #{cfgfile} --output=#{outfile}")
      end
    end
  end

  define_test :fio_on_regions do
    nr_sub_vols = 4
    sub_vol_size = meg(1024 + 128)


    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
			   :policy => Policy.new('smq', :migration_threshold => 10240),
			   :metadata_size => meg(128),
			   :cache_size => sub_vol_size,
			   :block_size => k(32),
			   :data_size => sub_vol_size * nr_sub_vols)
    stack.activate do |stack|
      sub_vg = TinyVolumeManager::VM.new
      sub_vg.add_allocation_volume(stack.cache)
      nr_sub_vols.times do |n|
        sub_vg.add_volume(linear_vol("vol#{n}", sub_vol_size))
      end

      nr_sub_vols.times do |n|
	with_dev(sub_vg.table("vol#{n}")) do |vol|
	  8.times do |iter|
	    run_fio(vol, "vol#{n}-run#{iter}")
	    pp CacheStatus.new(stack.cache)
	  end
	end
      end
    end
  end

  def baseline(dev, name)
    sub_vol_size = meg(1024 + 128)

    vg = TinyVolumeManager::VM.new
    vg.add_allocation_volume(dev)
    vg.add_volume(linear_vol("vol", sub_vol_size))
    with_dev(vg.table("vol")) do |vol|
      run_fio(vol, name)
    end
  end

  define_test :fio_on_fast do
    baseline(@metadata_dev, "fast")
  end

  define_test :fio_on_slow do
    baseline(@data_dev, "slow")
  end
end

#----------------------------------------------------------------
