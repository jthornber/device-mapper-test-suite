require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/xml_format'
require 'dmtest/tests/thin-provisioning/metadata-generator'

#----------------------------------------------------------------

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

  def test_thin_check
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

      thin_check(@metadata_dev, '-q') do |stdout, stderr, e|
        assert(!e)
        assert_equal('', stdout)
        assert_equal('', stderr)
      end
    end
  end

  def test_thin_dump
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
