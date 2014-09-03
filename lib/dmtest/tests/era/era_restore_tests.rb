require 'dmtest/era_stack'
require 'dmtest/era_utils'
require 'dmtest/thinp-test'
require 'dmtest/test-utils'
require 'dmtest/utils'

require 'rspec/expectations'

#----------------------------------------------------------------

class EraRestoreTests < ThinpTestCase
  include EraUtils
  include Utils
  include DiskUnits
  extend TestUtils

  def make_stack(opts = Hash.new)
    EraStack.new(@dm, @metadata_dev, @data_dev, opts)
  end

  ERA7 = <<EOF
<blocks>
  <range begin="8192" end = "9216"/>
  <range begin="10240" end = "11264"/>
  <range begin="12288" end = "13312"/>
  <range begin="14336" end = "15360"/>
</blocks>
EOF

  ERA13 = <<EOF
<blocks>
  <range begin="14336" end = "15360"/>
</blocks>
EOF

  def io_load(s)
    checkpoints = []
    block_size = k(64) * 1024
    nr_blocks = dev_size(s.era) / block_size

    0.upto(nr_blocks - 1) do |block|
      checkpoints << s.checkpoint

      # we only wipe alternating blocks
      if (block.even?)
        ProcessControl.run("dd if=/dev/zero of=#{s.era.path} oflag=direct bs=#{block_size * 512} seek=#{block} count=1")
      end
    end

    checkpoints
  end

  #--------------------------------

  def test_dump_and_restore_metadata
    checkpoints = nil

    s = make_stack(:format => true)
    s.activate_support_devs do
      s.activate_top_level do
        checkpoints = io_load(s)
      end

      blocks_changed_since(s.md, checkpoints[7]).should == ERA7.chomp
      blocks_changed_since(s.md, checkpoints[13]).should == ERA13.chomp

      s.dump_metadata do |xml_path1|
        s.restore_metadata(xml_path1)
      end
      
      blocks_changed_since(s.md, checkpoints[7]).should == ERA7.chomp
      blocks_changed_since(s.md, checkpoints[13]).should == ERA13.chomp

      # check the kernel is working
      s.activate_top_level do
        checkpoints = io_load(s)
      end
    end
  end
end

#----------------------------------------------------------------
