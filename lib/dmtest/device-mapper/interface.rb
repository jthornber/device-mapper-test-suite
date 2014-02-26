require 'dmtest/process'
require 'pathname'

module DM
  class DMInterface
    def create(path)
      ProcessControl.run("dmsetup create #{strip(path)} --notable")
    end

    # FIXME: duplication
    def load(path, table)
      Utils::with_temp_file('dm-table') do |f|
        debug "writing table: #{table.to_embed}"
        f.puts table.to_s
        f.flush
        ProcessControl.run("dmsetup load #{strip(path)} #{f.path}")
      end
    end

    def load_ro(path, table)
      Utils::with_temp_file('dm-table') do |f|
        debug "writing table: #{table.to_embed}"
        f.puts table.to_s
        f.flush
        ProcessControl.run("dmsetup load --readonly #{strip(path)} #{f.path}")
      end
    end

    def suspend(path)
      ProcessControl.run("dmsetup suspend #{strip(path)}")
    end

    def suspend_noflush(path)
      ProcessControl.run("dmsetup suspend --noflush #{strip(path)}")
    end

    def resume(path)
      ProcessControl.run("dmsetup resume #{strip(path)}")
    end

    def remove(path)
      # FIXME: lift this retry?
      Utils.retry_if_fails(5.0) do
        if File.exists?(path)
          ProcessControl.run("dmsetup remove #{strip(path)}")
        end
      end
    end

    def message(path, sector, *args)
      ProcessControl.run("dmsetup message #{strip(path)} #{sector} #{args.join(' ')}")
    end

    def status(path, *args)
      ProcessControl.run("dmsetup status #{args.join(' ')} #{strip(path)}")
    end

    def table(path)
      ProcessControl.run("dmsetup table #{strip(path)}")
    end

    def info(path)
      ProcessControl.run("dmsetup info #{strip(path)}")
    end

    def wait(path, event_nr)
      # FIXME: it would be nice if this returned the new event nr
      ProcessControl.run("dmsetup wait #{strip(path)} #{event_nr}")
    end

    private
    def strip(path)
      Pathname(path).basename.to_s
    end
  end
end
