module FioSubVolumeScenario
  include Utils

  def do_fio(dev, fs_type, opts = Hash.new)
    outfile = opts.fetch(:outfile, AP("fio.out"))
    cfgfile = opts.fetch(:cfgfile, LP("tests/cache/fio.config"))
    fs = FS::file_system(fs_type, dev)
    fs.format

    fs.with_mount('./fio_test', :discard => true) do
      Dir.chdir('./fio_test') do
        ProcessControl.run("fio #{cfgfile} --output=#{outfile}")
      end
    end
  end

  def fio_sub_volume_scenario(dev, &wait)
    subvolume_count = 4
    subvolume_size = meg(256)

    tvm = TinyVolumeManager::VM.new

    if subvolume_count * subvolume_size > dev_size(dev)
      raise RuntimeError, "data device not big enough"
    end

    tvm.add_allocation_volume(dev, 0, subvolume_count * subvolume_size)
    1.upto(subvolume_count) do |n|
      tvm.add_volume(linear_vol("linear_#{n}", subvolume_size))
    end

    # the test runs fio over each of these sub volumes in turn with
    # a sleep in between for the cache to sort itself out.
    1.upto(subvolume_count) do |n|
      with_dev(tvm.table("linear_#{n}")) do |subvolume|
        report_time("fio across subvolume #{n}", STDERR) do
          do_fio(subvolume, :ext4, :outfile => AP("fio_#{n}.out"))
        end

        wait.call
      end
    end
  end
end
