require 'dmtest/pattern_stomper'
require 'dmtest/test-utils'
require 'dmtest/era_stack'
require 'dmtest/era_utils'
require 'dmtest/thinp-test'
require 'dmtest/utils'

require 'rspec/expectations'

#----------------------------------------------------------------

class EraTrackingTests < ThinpTestCase
  include EraUtils
  include Utils
  include DiskUnits
  extend TestUtils

  def make_stack(opts = Hash.new)
    EraStack.new(@dm, @metadata_dev, @data_dev, opts)
  end

  #--------------------------------

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

  define_test :wiped_blocks_have_increasing_eras do
    s = make_stack(:format => true)
    s.activate_support_devs do
      @checkpoints = []
      s.activate_top_level do

        block_size = k(64) * 1024
        nr_blocks = dev_size(s.era) / block_size

        0.upto(nr_blocks - 1) do |block|
          @checkpoints << s.checkpoint

          # we only wipe alternating blocks
          if (block.even?)
            ProcessControl.run("dd if=/dev/zero of=#{s.era.path} oflag=direct bs=#{block_size * 512} seek=#{block} count=1")
          end
        end
      end

      blocks_changed_since(s.md, @checkpoints[7]).should == ERA7.chomp
      blocks_changed_since(s.md, @checkpoints[13]).should == ERA13.chomp
    end
  end

  define_test :pausing_does_not_effect_tracking do
    s = make_stack(:format => true)
    s.activate_support_devs do
      @checkpoints = []
       s.activate_top_level do
        block_size = k(64) * 1024
        nr_blocks = dev_size(s.era) / block_size

        0.upto(nr_blocks - 1) do |block|
          @checkpoints << s.checkpoint

          # we only wipe alternating blocks
          if (block.even?)
            ProcessControl.run("dd if=/dev/zero of=#{s.era.path} oflag=direct bs=#{block_size * 512} seek=#{block} count=1")

            s.era.pause do
              sleep 1
            end
          end
        end
      end

      blocks_changed_since(s.md, @checkpoints[7]).should == ERA7.chomp
      blocks_changed_since(s.md, @checkpoints[13]).should == ERA13.chomp
    end
  end

  define_test :many_eras_does_not_exhaust_metadata do
    s = make_stack(:format => true)
    s.activate_support_devs do
       s.activate_top_level do
        block_size = k(64) * 1024
        nr_blocks = dev_size(s.era) / block_size

        100.times do
          0.upto(nr_blocks - 1) do |block|
            c = s.checkpoint

            status = EraStatus.new(s.era)
            STDERR.puts "current_era #{c}, metadata #{status.md_used}/#{status.md_total}"

            ProcessControl.run("dd if=/dev/zero of=#{s.era.path} oflag=direct bs=#{block_size * 512} seek=#{block} count=1")
          end
        end
      end

      s.activate_top_level do
        # just checking
      end
    end
  end

  define_test :repeated_dumps_are_identical do
    s = make_stack(:format => true)
    s.activate_support_devs do
      s.activate_top_level do
        block_size = k(64) * 1024
        nr_blocks = dev_size(s.era) / block_size

        0.upto(nr_blocks - 1) do |block|
          c = s.checkpoint

          status = EraStatus.new(s.era)
          STDERR.puts "current_era #{c}, metadata #{status.md_used}/#{status.md_total}"

          ProcessControl.run("dd if=/dev/zero of=#{s.era.path} oflag=direct bs=#{block_size * 512} seek=#{block} count=1")
        end
      end

      output1 = File.read(s.dump_metadata(:logical => true))
      output2 = File.read(s.dump_metadata(:logical => true))

      output2.should == output1
    end
  end

  define_test :dumps_do_not_change_without_io do
    s = make_stack(:format => true)
    s.activate_support_devs do
       s.activate_top_level do
        block_size = k(64) * 1024
        nr_blocks = dev_size(s.era) / block_size

        0.upto(nr_blocks - 1) do |block|
          output1 = output2 = nil
          c = s.checkpoint

          status = EraStatus.new(s.era)
          STDERR.puts "current_era #{c}, metadata #{status.md_used}/#{status.md_total}"

          ProcessControl.run("dd if=/dev/zero of=#{s.era.path} oflag=direct bs=#{block_size * 512} seek=#{block} count=1")

          s.era.pause do
            output1 = s.dump_metadata(:logical => true)
          end

          s.era.pause do
            output2 = s.dump_metadata(:logical => true)
          end

          output2.should == output1
        end
      end
    end
  end

  define_test :reloads_do_not_change_dumps do
    output1 = output2 = output3 = nil

    s = make_stack(:format => true)
    s.activate_support_devs do
      s.activate_top_level do
        wipe_device(s.era)
      end

      output1 = s.dump_metadata(:logical => true)

      s.activate_top_level do
        s.era.pause do
          output2 = s.dump_metadata(:logical => true)
        end
      end

      output3 = s.dump_metadata(:logical => true)
    end

    output2.should == output1
    output3.should == output2
  end

  define_test :writes_to_already_written_areas_do_not_change_dumps do
    output1 = output2 = output3 = nil

    s = make_stack(:format => true)
    s.activate_support_devs do
      s.activate_top_level do
        wipe_device(s.era)
        
        s.era.pause do
          output1 = s.dump_metadata(:logical => true)
        end

        wipe_device(s.era)

        s.era.pause do
          output2 = s.dump_metadata(:logical => true)
        end
      end
    end

    output2.should == output1
  end
end

#----------------------------------------------------------------
