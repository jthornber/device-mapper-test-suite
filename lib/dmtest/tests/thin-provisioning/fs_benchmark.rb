#!/usr/bin/env ruby

require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/git'
require 'dmtest/status'
require 'dmtest/thinp-test'
require 'dmtest/xml_format'

#----------------------------------------------------------------

class FSBench < ThinpTestCase
  include GitExtract
  include Utils
  include XMLFormat
  extend TestUtils

  def timed_block(desc, &block)
    lambda {report_time(desc, &block)}
  end

  def bonnie(dir = '.')
    ProcessControl::run("bonnie++ -d #{dir} -r 0 -u root -s 2048")
  end

  def extract(dev)
      git_prepare(dev, :ext4)
      git_extract(dev, :ext4, TAGS[0..5])
  end

  def with_fs(dev, fs_type)
    puts "formatting ..."
    fs = FS::file_system(fs_type, dev)
    fs.format(:disard => false)

    fs.with_mount('./bench_mnt') do
      Dir.chdir('./bench_mnt') do
        yield
      end
    end
  end

  def dump_metadata(pool, dev, path)
    pool.message(0, "reserve_metadata_snap")
    status = PoolStatus.new(pool)
    ProcessControl::run("thin_dump #{dev} -m #{status.held_root} > #{path}")
    pool.message(0, "release_metadata_snap")
  end

  def raw_test(&block)
    with_fs(@data_dev, :xfs, &timed_block("raw test", &block))
  end

  def thin_test(&block)
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @size / 2, 0) do |thin|
        with_fs(thin, :xfs, &timed_block("thin test", &block))
      end
    end
  end

  def rolling_snap_test(&block)
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @size / 2, 0) do |thin|
        body = lambda do
          report_time("rolling snap") do
            block.call(pool, thin)
          end
        end

        with_fs(thin, :xfs) do
          report_time("unprovisioned", &body)

          thin.pause {pool.message(0, "create_snap 1 0")}

          report_time("re-running with snap", &body)
          report_time("broken sharing", &body)

          pool.message(0, "delete 1")
          thin.pause do
            pool.message(0, "create_snap 1 0")
          end

          report_time("and again, with a different snap", &body)
          report_time("broken sharing", &body)
        end
      end
    end
  end

  define_test :bonnie_raw_device do
    raw_test {bonnie}
  end

  define_test :bonnie_thin do
    thin_test {bonnie}
  end

  define_test :bonnie_rolling_snap do
    dir = Dir.pwd
    n = 0

    body = lambda do |pool, thin|
      bonnie
      dump_metadata(pool, @metadata_dev, "#{dir}/bonnie_#{n}.xml");
      n += 1
    end

    rolling_snap_test(&body)
  end

  define_test :git_extract_raw do
    with_standard_linear do |linear|
      extract(linear)
    end
  end

  define_test :git_extract_thin do
    with_standard_pool(@size, :zero => false, :block_size => 2048) do |pool|
      with_new_thin(pool, @size, 0) do |thin|
        extract(thin)
      end
    end
  end

  define_test :fio_thin_unallocated do
    # We're interested in the iops with fast devices, so carve up the
    # metadata dev.
    size = gig(10)

    tvm = TinyVolumeManager::VM.new
    tvm.add_allocation_volume(@metadata_dev)
    tvm.add_volume(linear_vol('metadata', gig(1)))
    tvm.add_volume(linear_vol('data', size))

    with_devs(tvm.table('metadata'),
              tvm.table('data')) do |md, data|

      wipe_device(md, 8)

      stack = PoolStack.new(@dm, data, md, :zero => false, :block_size => 2048)
      stack.activate do |pool|
        with_new_thin(pool, size, 0) do |thin|
          with_fs(thin, :ext4) do
            outfile = AP("fio.out")
            cfgfile = LP("tests/thin-provisioning/fio.config")
            ProcessControl.run("fio #{cfgfile} --output=#{outfile}")
          end
        end
      end
    end
  end

  define_test :fio_thin_preallocated do
    # We're interested in the iops with fast devices, so carve up the
    # metadata dev.
    size = gig(90)

    tvm = TinyVolumeManager::VM.new
    tvm.add_allocation_volume(@metadata_dev)
    tvm.add_volume(linear_vol('metadata', gig(1)))
    tvm.add_volume(linear_vol('data', size))

    with_devs(tvm.table('metadata'),
              tvm.table('data')) do |md, data|

      wipe_device(md, 8)

      stack = PoolStack.new(@dm, data, md, :zero => false, :block_size => 2048)
      stack.activate do |pool|
        with_new_thin(pool, size, 0) do |thin|
          wipe_device(thin)
          with_fs(thin, :ext4) do
            outfile = AP("fio.out")
            cfgfile = LP("tests/thin-provisioning/fio.config")
            ProcessControl.run("fio #{cfgfile} --output=#{outfile}")
            # `perf record --call-graph dwarf -o /tmp/perf.data -F 99 -- fio #{cfgfile} --output=#{outfile}`
          end
        end
      end
    end
  end
  
  define_test :fio_thick do
    # We're interested in the iops with fast devices, so carve up the
    # metadata dev.
    size = gig(90)

    tvm = TinyVolumeManager::VM.new
    tvm.add_allocation_volume(@metadata_dev)
    tvm.add_volume(linear_vol('data', size))

    with_dev(tvm.table('data')) do |vol|
      sleep(1)
      with_fs(vol, :ext4) do
        outfile = AP("fio.out")
        cfgfile = LP("tests/thin-provisioning/fio.config")
        ProcessControl.run("fio #{cfgfile} --output=#{outfile}")
      end
    end
  end
  
  def _test_git_extract_rolling_snap
    dir = Dir.pwd
    n = 0

    body = lambda do |pool, thin|
      extract(thin)
      dump_metadata(pool, @metadata_dev, "#{dir}/git_extract_#{n}.xml");
      n += 1
    end

    rolling_snap_test(&body)
  end
end
