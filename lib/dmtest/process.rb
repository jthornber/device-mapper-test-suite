require 'dmtest/log'

#----------------------------------------------------------------

module ProcessControl
  class ExitError < RuntimeError
    attr_accessor :error_code

    def initialize(cmd, error_code)
      super(cmd)
      @error_code = error_code
    end
  end

  class LogConsumer
    attr_reader :stdout_lines, :stderr_lines

    def initialize
      @stdout_lines = Array.new
      @stderr_lines = Array.new
    end

    def self.log_array(nm, a)
      if a.length > 0
        debug "#{nm}:\n" + a.map {|l| "    " + l}.join("\n")
      end
    end

    def stdout(line)
      @stdout_lines << line
    end

    def stdout_end
      LogConsumer.log_array('stdout', @stdout_lines)
    end

    def stderr(line)
      @stderr_lines << line
    end

    def stderr_end
      LogConsumer.log_array('stderr', @stderr_lines)
    end
  end

  class Child
    def initialize(consumer, *cmd)
      @consumer = consumer

      @cmd_line = cmd.join(' ')
      debug "executing: '#{@cmd_line}'"

      cld_in = IO.pipe
      cld_out = IO.pipe
      cld_err = IO.pipe

      @pid = fork do
        cld_in[1].close
        cld_out[0].close
        cld_err[0].close

        STDIN.reopen(cld_in[0])
        STDOUT.reopen(cld_out[1])
        STDERR.reopen(cld_err[1])

        exec(@cmd_line)
      end

      # we're not sending any input yet
      cld_in[0].close
      cld_in[1].close

      cld_out[1].close
      cld_err[1].close

      # kick off threads to gather output
      @stdout_tid = Thread.new(cld_out[0]) do |p|
        while line = p.gets
          @consumer.stdout(line.chomp)
        end
        @consumer.stdout_end
        p.close
      end

      @stderr_tid = Thread.new(cld_err[0]) do |p|
        while line = p.gets
          @consumer.stderr(line.chomp)
        end
        @consumer.stderr_end
        p.close
      end
    end

    def wait
      pid, exit_status = Process.wait2(@pid)

      @stdout_tid.join
      @stderr_tid.join

      if exit_status != 0
        debug "command failed with '#{exit_status}': #{@cmd_line}"
        raise ExitError.new("command failed: #{@cmd_line}", exit_status.exitstatus)
      end

      exit_status
    end

    # blocks until process has exited
    def interrupt
      Process.kill('INT', @pid)
      wait
    end
  end

  def self.really_run(consumer, *cmd)
    p = Child.new(consumer, *cmd)
    p.wait
  end

  def self.run_(default, *cmd)
    c = LogConsumer.new
    ProcessControl.really_run(c, *cmd)
    c.stdout_lines.join("\n")
  end

  def self.capture(*cmd)
    e = false

    c = LogConsumer.new
    begin
      ProcessControl.really_run(c, *cmd)
    rescue ExitError => e
      e = true
    end

    [c.stdout_lines.join("\n"), c.stderr_lines.join("\n"), e]
  end

  def self.system(default, *cmd)
    run_(default, *cmd)
  end

  def self.run(*cmd)
    run_('', *cmd)
  end

  def self.sleep(duration)
    Kernel.sleep(duration)
  end
end

#----------------------------------------------------------------
