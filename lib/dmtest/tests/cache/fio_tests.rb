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
require 'tempfile'

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

  JOB_FILE=<<EOF
[randrw]
blocksize=64k
norandommap
random_distribution=random
rw=randrw
iodepth=16
overwrite=0
rwmixread=50
fsync_on_close=1
direct=1
runtime=60
ioengine=libaio
time_based

EOF

  def run_fio(dev, name, file_size)
    outfile = AP("fio-#{name}.out")
    size_in_meg = file_size / meg(1)

    fs = FS::file_system(:ext4, dev)
    fs.format(:discard => false)
    fs.with_mount('./fio_test', :discard => false) do
      Dir.chdir('./fio_test') do
	cfgfile = Tempfile.new('fio-job')
	begin
	  cfgfile.write(JOB_FILE)
	  cfgfile.write("size=#{size_in_meg}m")  # FIXME: finish
	ensure
	  cfgfile.close
	end
	ProcessControl.run("fio #{cfgfile.path} --output=#{outfile}")
	STDERR.puts ProcessControl.run("grep iops #{outfile}")
	#cfgfile.unlink
      end
    end
  end

  def region_test(fio_file_size)
    nr_sub_vols = 4
    # add a bit extra for the fs overhead
    fio_file_size = fio_file_size + 5 * (fio_file_size / 100);
    sub_vol_size = fio_file_size + meg(512)

    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
			   :policy => Policy.new('smq', :migration_threshold => 1024),
			   :metadata_size => meg(128),
			   :cache_size => fio_file_size,
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
	  2.times do |iter|
	    run_fio(vol, "vol#{n}-run#{iter}", fio_file_size)
	    status = CacheStatus.new(stack.cache)
	    #STDERR.puts "#{status.promotions} promotions, #{status.demotions} demotions, #{status.writebacks} writebacks"
	  end
	end
      end
    end

  end

  define_test :fio_on_regions do
    region_test(gig(1))
  end

  def baseline(dev, name)
    file_size = meg(1024)
    sub_vol_size = file_size + meg(128)

    vg = TinyVolumeManager::VM.new
    vg.add_allocation_volume(dev)
    vg.add_volume(linear_vol("vol", sub_vol_size))
    with_dev(vg.table("vol")) do |vol|
      run_fio(vol, name, file_size)
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
