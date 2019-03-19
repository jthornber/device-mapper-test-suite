require 'dmtest/log'
require 'dmtest/process'

#----------------------------------------------------------------

class Git
  attr_reader :origin, :dir

  def self.clone(origin, dir)
    ProcessControl.run("git clone #{origin} #{dir}")
    Git.new(dir)
  end

  def initialize(origin)
    raise "not a git directory" unless Pathname.new("#{origin}/.git").exist?
    @origin = origin
  end

  def in_repo(&block)
    Dir.chdir(@origin, &block)
  end

  def checkout(tag)
    ProcessControl.run("cd #{@origin} && git checkout #{tag}")
  end

  def delete
    ProcessControl.run("rm -rf #{origin}")
  end
end

#----------------------------------------------------------------

module GitExtract
  def drop_caches
    ProcessControl.run('echo 3 > /proc/sys/vm/drop_caches')
  end

  TAGS = %w(v2.6.12 v2.6.13 v2.6.14 v2.6.15 v2.6.16 v2.6.17 v2.6.18 v2.6.19
            v2.6.20 v2.6.21 v2.6.22 v2.6.23 v2.6.24 v2.6.25 v2.6.26 v2.6.27 v2.6.28
            v2.6.29 v2.6.30 v2.6.31 v2.6.32 v2.6.33 v2.6.34 v2.6.35 v2.6.36 v2.6.37
            v2.6.38 v2.6.39 v3.0 v3.1 v3.2)

  def git_prepare_(dev, fs_type, format_opts = {})
    fs = FS::file_system(fs_type, dev)
    STDERR.puts "formatting ..."
    fs.format(format_opts)

    fs.with_mount('./kernel_builds', :discard => false) do
      Dir.chdir('./kernel_builds') do
        STDERR.puts "getting repo ..."
        repo = Git.clone('/root/linux-github', 'linux')
      end
    end
  end

  def git_prepare(dev, fs_type)
    report_time("git_prepare", STDERR) {git_prepare_(dev, fs_type)}
  end

  def git_prepare_no_discard(dev, fs_type)
    report_time("git_prepare", STDERR) {git_prepare_(dev, fs_type, :discard => false)}
  end

  def git_extract(dev, fs_type, tags = TAGS)
    fs = FS::file_system(fs_type, dev)
    fs.with_mount('./kernel_builds', :discard => false) do
      Dir.chdir('./kernel_builds') do
        repo = Git.new('linux')

        repo.in_repo do
          report_time("extract all versions", STDERR) do
            tags.each do |tag|
              STDERR.puts "Checking out #{tag} ..."
              report_time("checking out #{tag}") do
                repo.checkout(tag)
                ProcessControl.run('sync')
                drop_caches
              end
            end
          end
        end
      end
    end
  end

  def git_extract_each(dev, fs_type, tags = TAGS, &block)
    fs = FS::file_system(fs_type, dev)
    fs.with_mount('./kernel_builds', :discard => false) do
      Dir.chdir('./kernel_builds') do
        repo = Git.new('linux')

        repo.in_repo do
          report_time("extract all versions", STDERR) do
            tags.each do |tag|
              STDERR.puts "Checking out #{tag} ..."
              report_time("checking out #{tag}") do
                repo.checkout(tag)
                ProcessControl.run('sync')
                if block
                  block.call
                end
                drop_caches
              end
            end
          end
        end
      end
    end
  end
end

#----------------------------------------------------------------
