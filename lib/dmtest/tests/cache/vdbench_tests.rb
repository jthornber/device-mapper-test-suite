require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/tags'
require 'dmtest/thinp-test'
require 'dmtest/cache-status'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'dmtest/tvm.rb'
require 'dmtest/cache_stack'
require 'dmtest/cache_utils'
require 'dmtest/cache_policy'

require 'rspec/expectations'

#----------------------------------------------------------------

class VDBenchTests < !ThinpTestCase
  include Tags
  include Utils
  include DiskUnits
  include CacheUtils
  extend TestUtils

  POLICY_NAMES = %w(mq smq)
  IO_MODES = [:writethrough, :writeback]

  def setup
    super
    @data_block_size = k(32)
  end

  def write_vdbench_param_file
    File.open('vdbench.cfg', 'w+') do |f|
      text = <<EOF
data_errors=1
validate=yes

fsd=fsd1,anchor=/root/dmtest/test_fs/anchor,depth=1,width=1,files=1000,size=80m,wss=25g

fwd=default,xfersizes=(4k,30,8k,30,64k,30,512k,10),fileio=random,fileselect=random,threads=16,
stopafter=100
fwd=fwd1,fsd=fsd1,rdpct=75
fwd=fwd2,fsd=fsd1,rdpct=55

rd=rd1,fwd=fwd*,fwdrate=max,format=yes,elapsed=120,interval=1

EOF

      f.puts text
    end
  end

  #--------------------------------

  def vdbench(policy, io_mode)
    s = CacheStack.new(@dm, @metadata_dev, @data_dev,
                       :data_size => gig(100),
                       :cache_size => gig(1),
                       :io_mode => io_mode)
    s.activate do
      fs = FS.file_system(:xfs, s.cache)
      fs.format
      fs.with_mount('./test_fs', :discard => false) do
        Dir.chdir('./test_fs') do
          write_vdbench_param_file

          report_time("vdbench") do
            ProcessControl::run("vdbench -f vdbench.cfg")
          end
        end
      end
    end
  end

  define_tests_across(:vdbench, POLICY_NAMES, IO_MODES)
end

#----------------------------------------------------------------
