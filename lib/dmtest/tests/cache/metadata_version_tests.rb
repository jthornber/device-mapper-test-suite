require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/cache_stack'
require 'dmtest/cache_policy'

require 'rspec'

#----------------------------------------------------------------

class MetadataVersionTests < ThinpTestCase
  include Tags
  include Utils
  include DiskUnits
  extend TestUtils

  def setup
    super
    @data_block_size = meg(1)
  end

  def test_kernel_detects_bad_metadata_version
    # generate some xml metadata
    xml_file = 'metadata.xml'
    ProcessControl.run("cache_xml create --nr-cache-blocks uniform[100..500] --nr-mappings uniform[50..100] > #{xml_file}")

    # bring up the metadata device
    stack = CacheStack.new(@dm, @metadata_dev, @data_dev,
                           :format => true, :data_size => gig(1))
    stack.activate_support_devs do |stack|
      # restore from xml
      ProcessControl.run("cache_restore -i #{xml_file} -o #{stack.md} --debug-override-metadata-version 12345")

      # Bring up the kernel cache target to validate the metadata

      # FIXME: use rspec's expect
      caught = false
      begin
        stack.activate_top_level {|stack|}
      rescue
        caught = true
      end

      assert(caught)
    end
  end
end

#----------------------------------------------------------------
