require 'dmtest/blktrace'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/thinp-test'
require 'dmtest/tests/thin-provisioning/metadata-generator'

#----------------------------------------------------------------

class ToolsTests < ThinpTestCase
  include Utils
  include BlkTrace
  include MetadataGenerator
  include TinyVolumeManager
  extend TestUtils

  def setup
    super
  end

  def forbidden_on_live_metadata(cmd)
    with_standard_pool(@size) do |pool|
      pool.message(0, "reserve_metadata_snap")

      with_new_thin(pool, @volume_size, 0) do |thin|
        assert_raises(ProcessControl::ExitError) do
          ProcessControl.run(cmd)
        end
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
    with_standard_pool(@size) do |pool|
      pool.message(0, "reserve_metadata_snap")

      with_new_thin(pool, @volume_size, 0) do |thin|
        ProcessControl.run(cmd)
      end
    end
  end

  define_test :you_cannot_run_thin_check_on_live_metadata do
    forbidden_on_live_metadata("thin_check #{@metadata_dev}")
  end

  define_test :you_cannot_run_thin_restore_on_a_live_metadata do
    metadata = create_metadata(5, 1024, :linear_array)

    Utils::with_temp_file('metadata_xml') do |file|
      write_xml(metadata, file)
      file.flush
      file.close

      forbidden_on_live_metadata("thin_restore -i #{file.path} -o #{@metadata_dev}")
    end
  end

  define_test :you_cannot_dump_live_metadata do
    forbidden_on_live_metadata("thin_dump #{@metadata_dev}")
  end

  define_test :you_can_dump_a_metadata_snapshot do
    allowed_on_live_metadata("thin_dump --metadata-snap #{@metadata_dev}")
  end

  #--------------------------------

  DUMP1 =<<EOF
<superblock uuid="" time="0" transaction="0" data_block_size="128" nr_data_blocks="0">
  <device dev_id="0" mapped_blocks="0" transaction="0" creation_time="0" snap_time="0">
  </device>
  <device dev_id="1" mapped_blocks="0" transaction="0" creation_time="0" snap_time="0">
  </device>
</superblock>
EOF

  DUMP2 =<<EOF
<superblock uuid="" time="0" transaction="0" data_block_size="128" nr_data_blocks="0">
  <device dev_id="0" mapped_blocks="16384" transaction="0" creation_time="0" snap_time="0">
    <range_mapping origin_begin="0" data_begin="0" length="16384" time="0"/>
  </device>
  <device dev_id="1" mapped_blocks="0" transaction="0" creation_time="0" snap_time="0">
  </device>
</superblock>
EOF

  DUMP3 =<<EOF
<superblock uuid="" time="0" transaction="0" data_block_size="128" nr_data_blocks="0">
  <device dev_id="0" mapped_blocks="16384" transaction="0" creation_time="0" snap_time="0">
    <range_mapping origin_begin="0" data_begin="0" length="16384" time="0"/>
  </device>
  <device dev_id="1" mapped_blocks="16384" transaction="0" creation_time="0" snap_time="0">
    <range_mapping origin_begin="0" data_begin="16384" length="16384" time="0"/>
  </device>
</superblock>
EOF

  def check_metadata_snap(pool, txt)
    metadata = nil
    expected = StringIO.new(txt)

    pool.message(0, "reserve_metadata_snap")
    begin
      Utils::with_temp_file('metadata_xml') do |file|
        ProcessControl::run("thin_dump -m #{@metadata_dev} > #{file.path}")
        file.rewind
        assert FileUtils.compare_stream(file, expected)
      end
    ensure
      pool.message(0, "release_metadata_snap")
    end
  end

  define_test :thin_dump_a_metadata_snap_of_an_active_pool do
    with_standard_pool(@size) do |pool|
      with_new_thins(pool, @volume_size, 0, 1) do |thin, thin2|
        check_metadata_snap(pool, DUMP1)
        wipe_device(thin)
        check_metadata_snap(pool, DUMP2)
        wipe_device(thin2)
        check_metadata_snap(pool, DUMP3)
      end
    end
  end

  #--------------------------------

  # This test repeatedly takes metadata snapshots whilst a thin volume
  # is repeatedly created, provisioned and deleted. See bz 1286500.
  define_test :metadata_snap_stress1 do
    with_standard_pool(@size) do |pool|
      thread1 = Thread.new(pool) do |pool|
        10.times do
          with_new_thin(pool, @volume_size, 0) do |thin|
            wipe_device(thin)
          end

          pool.message(0, "delete 0")
        end
      end

      while thread1.alive? do
        sleep 0.2

        pool.message(0, "reserve_metadata_snap")
        pool.message(0, "release_metadata_snap")
      end
    end
  end

  # A variant of the above that periodically takes the pool down to run thin_check
  define_test :metadata_snap_stress2 do
    10.times do |n|
      with_standard_pool(@size, :format => (n == 0)) do |pool|

        STDERR.puts "iteration #{n}"

        if n > 0
          pool.message(0, "release_metadata_snap")
          pool.message(0, "delete 0")
        end

        pool.message(0, "reserve_metadata_snap")
        with_new_thin(pool, @volume_size, 0) do |thin|
          wipe_device(thin)
        end
      end
    end
  end

  #--------------------------------

  def read_metadata
    dump_metadata(@metadata_dev) do |xml_path|
      File.open(xml_path, 'r') do |io|
        read_xml(io)            # this is the return value
      end
    end
  end

  def run_thin_ls(use_metadata_snap = false)
    thin_ls = {}
    input = `thin_ls #{use_metadata_snap ? "-m" : ""} -o DEV,EXCLUSIVE_BLOCKS #{@metadata_dev}`
    input.lines.each do |line|
      m = line.match(/\s*(\d+)\s+(\d+)/)
      if m
        thin_ls[m[1].to_i] = m[2].to_i
      end
    end

    thin_ls
  end

  define_test :thin_ls do
    @volume_size = meg(1400)

    with_standard_pool(@size, :format => true) do |pool|
      stomper = nil;

      with_new_thin(pool, @volume_size, 0) do |thin|
        stomper = PatternStomper.new(thin.path, @data_block_size, :needs_zero => true)
        stomper.stamp(20)

        with_new_snap(pool, @volume_size, 1, 0, thin) do |snap1|
          stomper2 = stomper.fork(snap1.path)
          stomper2.stamp(20)
          stomper2.verify(0, 2)

          with_new_snap(pool, @volume_size, 2, 1, snap1) do |snap2|
            stomper3 = stomper2.fork(snap2.path)
            stomper3.stamp(20)
          end
        end
      end
    end

    md = read_metadata
    
    ref_counts = Hash.new(0)
    md.devices.each do |dev|
      dev.mappings.each do |m|
        m.length.times do |i|
          ref_counts[m.data_begin + i] += 1
        end
      end
    end

    thin_ls = run_thin_ls

    md.devices.each do |dev|
      tot = 0
      dev.mappings.each do |m|
        m.length.times do |i|
          if ref_counts[m.data_begin + i] == 1
            tot += 1
          end
        end
      end

      assert_equal(tot, thin_ls[dev.dev_id])
    end

    with_standard_pool(@size, :format => false) do |pool|
      pool.message(0, "reserve_metadata_snap")
      thin_ls2 = run_thin_ls(true)
      pool.message(0, "release_metadata_snap")

      assert_equal(thin_ls, thin_ls2)
    end
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
    ProcessControl::run("thin_repair -i #{tmp_file} -o #{md}")
  end

  def check_metadata(md)
    ProcessControl::run("thin_check #{md}")
  end

  define_test :thin_repair_repeatable do
    # We want to use a little metadata dev for this since we copy it
    # to a temp file.
    tvm = VM.new
    tvm.add_allocation_volume(@metadata_dev)
    tvm.add_volume(linear_vol('metadata', meg(50)))

    with_dev(tvm.table('metadata')) do |md|
      stack = PoolStack.new(@dm, @data_dev, md,
                            :data_size => @size, :format => true)
      stack.activate do |pool|
        with_new_thin(pool, @volume_size, 0) do |thin|
          wipe_device(thin)
        end
      end

      corrupt_metadata(md)
      repair_metadata(md)
      check_metadata(md)

      corrupt_metadata(md)
      repair_metadata(md)
      check_metadata(md)
    end
  end

  #--------------------------------

  define_test :you_cannot_run_thin_trim_on_live_metadata do
    forbidden_on_live_metadata("thin_trim --metadata-dev #{@metadata_dev} --data-dev #{@data_dev}")
  end

  define_test :you_cannot_run_thin_trim_on_live_data do
    forbidden_on_live_data("thin_trim --metadata-dev #{@metadata_dev} --data-dev #{@data_dev}")
  end

  define_test :thin_trim_discards_correct_area do
    traces = nil
    @volume_size = gig(4)

    with_discardable_dev(@size) do |data_dev|
      with_custom_data_pool(data_dev, @size) do |pool|
        STDERR.puts "@size = #{@size}, @volume_size = #{@volume_size}"
        with_new_thin(pool, @volume_size, 0) do |thin|
          wipe_device(thin)
        end
      end

      sleep 5

      traces, _ = blktrace(@metadata_dev, data_dev) do
        ProcessControl.run("thin_trim --metadata-dev #{@metadata_dev} --data-dev #{data_dev}")
      end
    end

    pp traces
  end
end

#----------------------------------------------------------------
