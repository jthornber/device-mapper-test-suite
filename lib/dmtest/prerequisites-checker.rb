require 'dmtest/log'
require 'dmtest/process'

#----------------------------------------------------------------

module Prerequisites
  module Detail
    class ProgInPathCheck
      def initialize(prog)
        @prog = prog
      end

      def check
        begin
          ProcessControl.run("which #{@prog}")
        rescue
          raise "'#{@prog}' in not in path"
        end
      end
    end

    class RubyVersionCheck
      def initialize(pattern)
        @pattern = pattern
      end

      def check
        raise "wrong ruby version (expected #{pattern})" unless RUBY_VERSION =~ @pattern
      end
    end

    class Prerequisits
      def initialize
        @checked = false
        @checks = Array.new
      end

      def require_in_path(*progs)
        @checks = progs.map {|prog| ProgInPathCheck.new(prog)}
      end

      def require_ruby_version(pattern)
        @checks << RubyVersionCheck.new(pattern)
      end

      def add_requirements(&block)
        self.instance_eval(&block)
      end

      def check
        if !@checked
          @checks.each {|check| check.check}
          @checked = true
        end
      end
    end
  end

  def Prerequisites.requirements(&block)
    reqs = Detail::Prerequisits.new
    reqs.add_requirements(&block)
    reqs
  end
end

#----------------------------------------------------------------
