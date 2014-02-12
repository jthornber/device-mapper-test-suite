require 'dmtest/pattern_stomper'
require 'dmtest/test-utils'
require 'dmtest/tests/era/era_stack'
require 'dmtest/tests/era/era_utils'
require 'dmtest/thinp-test'
require 'dmtest/utils'

require 'rspec/expectations'

#----------------------------------------------------------------

class EraTrackingTests < ThinpTestCase
  include EraUtils
  include Utils
  include DiskUnits
  extend TestUtils

  def setup
    super
  end

  def make_stack(opts = Hash.new)
    EraStack.new(@dm, @metadata_dev, @data_dev, opts)
  end

  #--------------------------------

  ERA7 = <<EOF
<blocks>
  <range begin="6144" end = "7168"/>
  <range begin="8192" end = "9216"/>
  <range begin="10240" end = "11264"/>
  <range begin="12288" end = "13312"/>
  <range begin="14336" end = "15360"/>
</blocks>
EOF

  ERA13 = <<EOF
<blocks>
  <range begin="12288" end = "13312"/>
  <range begin="14336" end = "15360"/>
</blocks>
EOF

  def test_wiped_blocks_have_increasing_eras
    s = make_stack(:format => true)
    s.activate_support_devs do
       s.activate_top_level do

        block_size = k(64) * 1024
        nr_blocks = dev_size(s.era) / block_size

        0.upto(nr_blocks - 1) do |block|
          s.era.message(0, "checkpoint")

          # we only wipe alternating blocks
          if (block.even?)
            #STDERR.puts "wiping blocks #{1024 * block}..#{1024 * (block + 1)}"
            ProcessControl.run("dd if=/dev/zero of=#{s.era.path} oflag=direct bs=#{block_size * 512} seek=#{block} count=1")
          end
        end
      end

      blocks_changed_since(s.md, 7).should == ERA7.chomp
      blocks_changed_since(s.md, 13).should == ERA13.chomp
    end
  end
end

#----------------------------------------------------------------
