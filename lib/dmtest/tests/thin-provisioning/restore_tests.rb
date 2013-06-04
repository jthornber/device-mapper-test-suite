require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/xml_format'

#----------------------------------------------------------------

module MetadataGenerator
  include XMLFormat

  def data_dev_blocks
    dev_size(@data_dev) / @data_block_size
  end

  def create_linear_metadata(dev_count, dev_size)
    superblock = Superblock.new("uuid here", 0, 1, 128, data_dev_blocks)

    devices = Array.new
    offset = 0
    0.upto(dev_count - 1) do |dev|
      nr_mappings = dev_size
      mappings = Array.new
      1.upto(nr_mappings) {|n| mappings << Mapping.new(n, offset + n, 1, 1)}
      devices << Device.new(dev, nr_mappings, 0, 0, 0, mappings)

      offset += nr_mappings
    end

    Metadata.new(superblock, devices)
  end

  def create_metadata(dev_count, dev_size, block_mapper)
    nr_data_blocks = dev_size * dev_count
    superblock = Superblock.new("uuid here", 0, 1, 128, data_dev_blocks)

    devices = Array.new
    offset = 0
    dest_blocks = self.send(block_mapper, nr_data_blocks)

    0.upto(dev_count - 1) do |dev|
      nr_mappings = dev_size
      mappings = Array.new
      0.upto(nr_mappings - 1) do |n|
        mappings << Mapping.new(n, dest_blocks[offset + n], 1, 1)
      end
      devices << Device.new(dev, nr_mappings, 0, 0, 0, mappings)

      offset += nr_mappings
    end

    Metadata.new(superblock, devices)
  end

  # allocators
  def linear_array(len)
    ary = Array.new
    (0..(len - 1)).each {|n| ary[n] = n}
    ary
  end

  def shuffled_array(len)
    ary = linear_array(len)

    (0..(len - 1)).each do |n|
      n2 = n + rand(len - n)
      tmp = ary[n]
      ary[n] = ary[n2]
      ary[n2] = tmp
    end

    ary
  end
end

class RestoreTests < ThinpTestCase
  include Tags
  include Utils
  include MetadataGenerator

  def setup
    super
  end

  tag :thinp_target
  tag :thinp_target, :slow

  # Uses io to prepare a simple metadata dev
  # FIXME: we need snapshots, and multiple thins in here
  def prepare_md
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) {|thin| dt_device(thin)}
    end
  end

  def test_dump_is_idempotent
    prepare_md

    dump_metadata(@metadata_dev) do |xml_path1|
      dump_metadata(@metadata_dev) do |xml_path2|
        assert_identical_files(xml_path1, xml_path2)
      end
    end
  end

  def test_dump_restore_dump_is_idempotent
    prepare_md

    dump_metadata(@metadata_dev) do |xml_path1|
      wipe_device(@metadata_dev)
      restore_metadata(xml_path1, @metadata_dev)

      dump_metadata(@metadata_dev) do |xml_path2|
        assert_identical_files(xml_path1, xml_path2);
      end
    end
  end
  def restore_mappings(nr_devs, dev_size, mapper)
    # We don't use the kernel for this test, instead just creating a
    # large complicated xml metadata file, and then restoring it.
    metadata = create_metadata(nr_devs, dev_size, mapper)

    Utils::with_temp_file('metadata_xml') do |file|
      write_xml(metadata, file)
      file.flush
      file.close
      restore_metadata(file.path, @metadata_dev)
    end

    ProcessControl.run("thin_check #{@metadata_dev}")
    metadata
  end

  def do_kernel_happy_test(allocator)
    n = 1000

    restore_mappings(4, n, allocator)
    dump_metadata(@metadata_dev) do |xml1|
      with_standard_pool(dev_size(@data_dev)) do |pool|
        with_thin(pool, n * 128, 0) {|thin| wipe_device(thin)}
      end

      # These devices were fully provisioned, so we check the mapping is
      # identical after the wipe.
      dump_metadata(@metadata_dev) do |xml2|
        assert_identical_files(xml1, xml2);
      end
    end
  end

  def test_kernel_happy_with_linear_restored_data
    do_kernel_happy_test(:linear_array)
  end

  def test_kernel_happy_with_random_restored_data
    do_kernel_happy_test(:shuffled_array)
  end

  def test_kernel_can_use_restored_volume
    # fully provision a dev
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @volume_size, 0) {|thin| wipe_device(thin)}
    end
    
    dump_metadata(@metadata_dev) do |xml_path1|
      wipe_device(@metadata_dev)
      restore_metadata(xml_path1, @metadata_dev)
      
      with_standard_pool(@size) do |pool|
        with_thin(pool, @volume_size, 0) {|thin| wipe_device(thin, 1000)}
      end

      # metadata shouldn't have changed, since thin was fully
      # provisioned.
      dump_metadata(@metadata_dev) do |xml_path2|
        assert_identical_files(xml_path1, xml_path2)
      end
    end
  end

  #--------------------------------

  def self.mk_cmd(c)
    define_method(c) do |*args, &block|
      stdout, stderr, e = ProcessControl.capture(c, *args)
      block.call(stdout, stderr, e)
    end
  end

  mk_cmd(:thin_check)
  mk_cmd(:thin_dump)
  mk_cmd(:thin_restore)

  TOOLS_VERSION = /0.1.5/
  CHECK_USAGE =<<EOF.chomp
Usage: thin_check [options] {device|file}
Options:
  {-q|--quiet}
  {-h|--help}
  {-V|--version}
EOF

  DUMP_USAGE =<<EOF.chomp
Usage: thin_dump [options] {device|file}
Options:
  {-h|--help}
  {-f|--format} {xml|human_readable}
  {-r|--repair}
  {-m|--metadata-snap}
  {-V|--version}
EOF

  RESTORE_USAGE =<<EOF.chomp
Usage: thin_restore [options]
Options:
  {-h|--help}
  {-i|--input} input_file
  {-o|--output} {device|file}
  {-V|--version}
EOF

  def check_version(method)
    check = lambda do |stdout, stderr, e|
      assert(!e)
      assert(TOOLS_VERSION.match(stdout))
    end

    send(method, '--version', &check)
    send(method, '-V', &check)
  end

  def check_help(method, usage)
    check = lambda do |stdout, stderr, e|
      assert(!e)
      assert_equal(usage, stdout)
    end

    send(method, '--help', &check)
    send(method, '-h', &check)
  end

  def test_thin_check
    check_version(:thin_check)
    check_help(:thin_check, CHECK_USAGE)

    thin_check() do |stdout, stderr, e|
      assert(e)
      assert(/No input file provided./.match(stderr))
    end

    Utils::with_temp_file('metadata') do |f|
      f.close
      thin_check(f.path) do |stdout, stderr, e|
        assert(e)
      end
    end

    Utils::with_temp_file('metadata') do |f|
      f.close
      thin_check(f.path, '-q') do |stdout, stderr, e|
        assert(e)
        assert_equal('', stdout)
        assert_equal('', stderr)
      end
    end

    metadata = create_metadata(1, 100, :linear_array)
    Utils::with_temp_file('metadata_xml') do |f|
      write_xml(metadata, f)
      f.flush
      f.close
      restore_metadata(f.path, @metadata_dev)

      thin_check(@metadata_dev, '-q') do |stdout, stderr, e|
        assert(!e)
        assert_equal('', stdout)
        assert_equal('', stderr)
      end

      thin_check(@metadata_dev) do |stdout, stderr, e|
        assert(!e)
        assert_equal('', stdout)
        assert_equal('', stderr)
      end
    end
  end

  def test_thin_dump
    check_version(:thin_dump)
    check_help(:thin_dump, DUMP_USAGE)

    thin_dump() do |stdout, stderr, e|
      assert(e)
      assert(/No input file provided./.match(stderr))
    end

    Utils::with_temp_file('metadata') do |f|
      f.close
      thin_dump(f.path) do |stdout, stderr, e|
        assert(e)
      end
    end
  end

  def test_thin_restore
    check_version(:thin_restore)
    check_help(:thin_restore, RESTORE_USAGE)

    thin_restore() do |stdout, stderr, e|
      assert(e)
      assert(/No input file provided./.match(stderr))
    end

    Utils::with_temp_file('metadata') do |f|
      f.close
      thin_restore(f.path) do |stdout, stderr, e|
        assert(e)
      end
    end

    metadata = create_metadata(1, 100, :linear_array)
    Utils::with_temp_file('metadata_xml') do |f|
      write_xml(metadata, f)
      f.flush
      f.close

      thin_restore('-o', @metadata_dev, '-i', f.path) do |stdout, stderr, e|
        assert(!e)
      end

      thin_restore('-o', @metadata_dev) do |stdout, stderr, e|
        assert(e)
      end

      thin_restore('-i', f.path) do |stdout, stderr, e|
        assert(e)
      end
    end
  end
end

#----------------------------------------------------------------
