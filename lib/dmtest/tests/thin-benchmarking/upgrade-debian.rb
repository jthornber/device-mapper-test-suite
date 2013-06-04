require 'config'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/status'
require 'dmtest/thinp-test'

#----------------------------------------------------------------

class DebianUpgrade < ThinpTestCase
  include Utils

  def with_fs(dev, fs_type)
    puts "formatting ..."
    fs = FS::file_system(fs_type, dev)
    fs.format

    fs.with_mount('./bench_mnt') do
      Dir.chdir('./bench_mnt') do
        yield
      end
    end
  end

  def test_debian_extract
    with_standard_pool(@size) do |pool|
      with_new_thin(pool, @size / 2, 0) do |thin|
        with_fs(thin, :xfs) do
          `debootstrap lenny .`
        end
      end
    end
  end
end

#----------------------------------------------------------------
