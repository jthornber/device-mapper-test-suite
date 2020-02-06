require 'dmtest/benchmarking'
require 'dmtest/log'
require 'dmtest/utils'
require 'dmtest/fs'
require 'dmtest/disk-units'
require 'dmtest/test-utils'
require 'pp'

#----------------------------------------------------------------

class FioBenchmark
  include Benchmarking
  include Utils

  def initialize(cache_stack, opts = Hash.new)
    @stack = cache_stack
    @nr_jobs = opts.fetch(:nr_jobs, 4)
    @size_m = opts.fetch(:size_m, 256)
    @read_percent = opts.fetch(:read_percent, 50)
    @mount_name = './fio_test'
    @fs_type = :ext4
  end

  def run
    @stack.activate_support_devs do
      prepare_test_files(@stack.origin)

      @stack.activate_top_level do
        report_time("FIO pass 1", STDERR) do
          fio_exec(@stack.cache)
        end

        report_time("FIO pass 2", STDERR) do
          fio_exec(@stack.cache)
        end
      end
    end
  end

  private
  
  def create_zeroed_file(filename, size_meg)
    ProcessControl.run("dd if=/dev/zero of=#{filename} bs=1M count=#{size_meg}")
  end

  def prepare_test_files(dev)
      # Format the fs and prep the test files.  Must be done before
      # attaching the cache to avoid squewing results.
      begin
        fs = FS::file_system(@fs_type, dev)
        fs.format(:discard => false)
	fs.with_mount(@mount_name, :discard => true) do
	  Dir.chdir(@mount_name) do
	    @nr_jobs.times do |job_nr|
	      filename = "testfile.#{job_nr}"
	      create_zeroed_file(filename, @size_m * 4)
      	    end
      	  end
      	end
      end
  end

  def write_job_file(file)
    open(file, 'w') do |f|
      f.puts "[randrw]"
      f.puts "norandommap"
      f.puts "random_distribution=zipf:0.8"
      f.puts "rw=randrw"
      f.puts "rwmixread=#{@read_percent}"
      f.puts "size=#{@size_m}m"
      f.puts "fadvise_hint=0"
      f.puts "blocksize=8k"
      f.puts "direct=1"
      f.puts "numjobs=#{@nr_jobs}"
      f.puts "nrfiles=1"
      f.puts "filename_format=testfile.$jobnum"
      f.puts "ioengine=libaio"
    end
  end

  def fio_exec(dev)
    outfile = AP("fio_dm_writecache.out")
    cfgfile = "./database-funtime.fio"

    fs = FS::file_system(@fs_type, @stack.cache)
    fs.with_mount(@mount_name, :discard => true) do
      Dir.chdir(@mount_name) do
        write_job_file(cfgfile)
        
        ProcessControl.run("fio #{cfgfile} --output=#{outfile}")
        ProcessControl.run('ls -l')
      end
    end
  end
end

#----------------------------------------------------------------

