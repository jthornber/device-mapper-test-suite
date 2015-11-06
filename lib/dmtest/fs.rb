require 'dmtest/log'
require 'dmtest/process'
require 'dmtest/prelude'
require 'pathname'

#----------------------------------------------------------------

module FS
  class BaseFS
    attr_accessor :dev, :mount_point

    def initialize(dev)
      @dev = dev
      @mount_point = nil
    end

    def format(opts = {})
      ProcessControl.run(mkfs_cmd(opts))
    end

    def mount(mount_point, opts = Hash.new)
      @mount_point = mount_point
      Pathname.new(mount_point).mkpath
      ProcessControl.run(mount_cmd(mount_point, opts))
    end

    def umount
      ProcessControl.run("umount #{@mount_point}")
      Pathname.new(@mount_point).delete
      @mount_point = nil
      check
    end

    def with_mount(mount_point, opts = Hash.new, &block)
      mount(mount_point, opts)
      bracket_(lambda {umount}, &block)
    end

    def check
      ProcessControl.run("echo 1 > /proc/sys/vm/drop_caches");
      ProcessControl.run(check_cmd)
    end
  end

  class Ext4 < BaseFS
    def mount_cmd(mount_point, opts); "mount #{dev} #{mount_point} #{opts[:discard] ? "-o discard" : ''}"; end
    def check_cmd; "fsck.ext4 -fn #{dev}"; end

    def mkfs_cmd(opts)
      discard_arg = opts.fetch(:discard, true) ? 'discard' : 'nodiscard'
      "mkfs.ext4 -F -E lazy_itable_init=1,#{discard_arg} #{dev}"
    end
  end

  class XFS < BaseFS
    def mount_cmd(mount_point, opts); "mount -o nouuid#{opts[:discard] ? ",discard" : ''} #{dev} #{mount_point}"; end
    def check_cmd; "xfs_repair -n #{dev}"; end

    def mkfs_cmd(opts)
      discard_arg = opts.fetch(:discard, true) ? '' : ' -K'
      "mkfs.xfs -f #{dev}#{discard_arg}"
    end
  end

  FS_CLASSES = {
    :ext4 => Ext4,
    :xfs => XFS
  }

  def FS.file_system(type, dev)
    unless FS_CLASSES.member?(type)
      raise "unknown filesystem type '#{type}'"
    end

    FS_CLASSES[type].new(dev)
  end
end

#----------------------------------------------------------------
