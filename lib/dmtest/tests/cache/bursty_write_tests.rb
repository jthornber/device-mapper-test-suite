require 'dmtest/git'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/cache_stack'
require 'dmtest/cache_policy'

#----------------------------------------------------------------

class BurstyWriteTests < ThinpTestCase
  include GitExtract
  include Tags
  include Utils
  include DiskUnits
  extend TestUtils

  MOUNT_DIR = './smallfile-mount'

  def run_smallfile
    nr_threads = 4
    nr_files = 10000
    op = 'create'

    ProcessControl.run("python ~/smallfile/smallfile_cli.py --top #{MOUNT_DIR} --fsync Y --file-size-distribution exponential --hash-into-dirs Y --files-per-dir 30 --dirs-per-dir 5 --threads #{nr_threads} --file-size 64 --operation #{op} --files #{nr_files}")
  end

  def do_smallfile(dev)
    fs = FS::file_system(:xfs, dev)
    fs.format
    fs.with_mount(MOUNT_DIR) do
      run_smallfile
    end
  end

  def run_git_load(dev)
    git_prepare(dev, :ext4)
    git_extract(dev, :ext4, TAGS[0..5])
  end

  def do_git_extract_cache(opts)
    i = opts.fetch(:nr_tags, 5)
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev, opts)
    stack.activate do |stack|
      run_git_load(stack.cache)
      pp CacheStatus.new(stack.cache)
    end
  end

  def cache_extract(cache_size)
    do_git_extract_cache(:policy => Policy.new('mq',
                                               :write_promote_adjustment => 0,
                                               :discard_promote_adjustment => 0,
                                               :migration_threshold => 2048),
                         :cache_size => cache_size,
                         :block_size => 512,
                         :data_size => gig(2))
  end

  #--------------------------------

  def test_smallfile_linear
    with_standard_linear(:data_size => gig(4)) do |linear|
      do_smallfile(linear)
    end
  end

  def test_smallfile_cache
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :data_size => gig(4),
                           :cache_size => meg(1024),
                           :policy => Policy.new('mq',
                                                 :write_promote_adjustment => 0,
                                                 :discard_promote_adjustment => 0,
                                                 :migration_threshold => 2048));
    stack.activate do |stack|
      do_smallfile(stack.cache)
      pp CacheStatus.new(stack.cache)
    end
  end

  #--------------------------------

  def test_git_extract_linear
    with_standard_linear(:data_size => gig(2)) do |linear|
      run_git_load(linear)
    end
  end

  def test_git_extract_cache_16
    cache_extract(meg(16))
  end

  def test_git_extract_cache_64
    cache_extract(meg(64))
  end

  def test_git_extract_cache_256
    cache_extract(meg(256))
  end

  def test_git_extract_cache_512
    cache_extract(meg(512))
  end
end

#----------------------------------------------------------------
