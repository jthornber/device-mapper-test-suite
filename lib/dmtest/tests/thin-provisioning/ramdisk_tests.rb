require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'

#----------------------------------------------------------------

# Tests prompted by a email on dm-devel from Jagan Reddy
class RamDiskTests < ThinpTestCase
  include Tags
  include Utils

  def setup
    super

    # I'm assuming you have set up 2G ramdisks (ramdisk_size=2097152 on boot)
    @data_dev = '/dev/ram1'

    if !$wiped_ramdisk
      wipe_device(@data_dev)
      $wiped_ramdisk = true
    end

    @size = 2097152 * 2         # sectors
    @volume_size = 1900000
    @data_block_size = 2 * 1024 * 8 # 8 M
  end

  def aio_stress(dev)
    count = 20
    total = 0.0

    1.upto(count) do
      output = ProcessControl.run("aio-stress -O -o 1 -c 16 -t 16 -d 256 #{dev} 2>&1")
      output = output.grep(/throughput/)

      m = /\(([0-9\.]+) /.match(output[0])

      if m
        STDERR.puts m[1]

        total += m[1].to_f
      else
        STDERR.puts "no match: #{output}"
      end
    end

    ProcessControl.run("cat /proc/meminfo")
    info "aio_stress throughput: #{total / count}"
  end

  tag :thinp_target

  def test_overwrite_a_linear_device
    linear_table = Table.new(LinearTarget.new(@volume_size, @data_dev, 0))
    with_dev(linear_table) {|linear_dev| wipe_device(linear_dev)}
  end

  def test_read_a_linear_device
    linear_table = Table.new(LinearTarget.new(@volume_size, @data_dev, 0))
    with_dev(linear_table) {|linear_dev| read_device_to_null(linear_dev)}
  end

  def test_read_ramdisk
    read_device_to_null('/dev/ram1')
  end

  def test_dd_benchmark
    with_standard_pool(@size, :zero => true) do |pool|
      info "wipe an unprovisioned thin device"
      with_new_thin(pool, @volume_size, 0) {|thin| wipe_device(thin)}

      info "wipe a fully provisioned thin device"
      with_thin(pool, @volume_size, 0) {|thin| read_device_to_null(thin)}

      info "wipe a snapshot of a fully provisioned device"
      with_new_snap(pool, @volume_size, 1, 0) {|snap| wipe_device(snap)}

      info "wipe a snapshot with no sharing"
      with_thin(pool, @volume_size, 1) {|snap| read_device_to_null(snap)}
    end
  end

  def test_raw_aio_stress
    aio_stress(@data_dev)
  end

  def test_linear_aio_stress
    linear_table = Table.new(LinearTarget.new(@volume_size, @data_dev, 0))
    with_dev(linear_table) do |linear_dev|
      aio_stress(linear_dev)
    end
  end

  def test_stacked_linear_aio_stress
    linear_table = Table.new(LinearTarget.new(@volume_size, @data_dev, 0))
    with_dev(linear_table) do |linear_dev|
      linear_table2 = Table.new(LinearTarget.new(@volume_size, linear_dev, 0))
      with_dev(linear_table2) do |linear_dev2|
        aio_stress(linear_dev2)
      end
    end
  end

  def test_thin_aio_stress
    with_standard_pool(@size, :zero => true) do |pool|
      info "wipe an unprovisioned thin device"
      with_new_thin(pool, @volume_size, 0) do |thin|
        wipe_device(thin)
        aio_stress(pool)
        # deferred_ios = count_deferred_ios do
        #   aio_stress(thin)
        # end

        # info "deferred ios: #{deferred_ios}"
      end
    end
  end

  def test_pool_aio_stress
    with_standard_pool(@size, :zero => true) do |pool|
      aio_stress(pool)
    end
  end

  def test_linear_stacked_on_pool_aio_stress
    with_standard_pool(@size, :zero => true) do |pool|
      table = Table.new(LinearTarget.new(@size, pool, 0))
      with_dev(table) do |linear|
        aio_stress(linear)
      end
    end
  end
end

#----------------------------------------------------------------
