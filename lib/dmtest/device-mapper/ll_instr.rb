require 'set'
require 'dmtest/string/indent'
require 'dmtest/string/string-table'

#----------------------------------------------------------------

# FIXME: add instructions for input and output.  Input should include
# a timeout.

module DM::LowLevel
  class Instruction
    attr_accessor :op, :args

    def initialize(op, *args)
      @op = op
      @args = args
    end

    def [](n)
      @args[n]
    end

    def []=(n, v)
      @args[n] = v
    end

    def each(&block)
      @args.each(&block)
    end
  end

  #--------------------------------

  class ProgramFormatter
    attr_reader :instrs, :strings

    def initialize(instructions)
      @instrs = instructions
      @strings = StringUtils::StringTable.new
      build_string_hash
    end

    def format(out)
      @e = StringUtils::Emitter.new(out, 4)
      pp_strings
      pp_instrs
    end

    private
    def numeric?(arg)
      arg.class == Fixnum
    end

    def build_string_hash
      @instrs.each do |i|
        i.each do |s|
          @strings.add(s.to_s) unless numeric?(s)
        end
      end
    end

    def pp_strings
      @strings.each do |k, v|
        @e.emit ".string #{v}"
        @e.indent do
          k.lines.each do |l|
            @e.emit "        #{l}"
          end
        end
        @e.emit
      end
    end

    def pp_instrs
      @e.emit ".main"
      @e.indent do
        @instrs.each do |i|
          pp_instr(i)
        end
      end
    end

    def has_args?(i)
      i.args.length > 0
    end

    def pp_instr(i)
      case i.op
      when :label
        pp_label_instr(i)

      when :jump, :jump_on_fail
        pp_jump_instr(i)

      else
        pp_simple_instr(i)
      end
    end

    def pp_label_instr(i)
      @e.undent do
        @e.emit
        @e.emit ".#{i.args[0]}"
      end
    end

    def pp_jump_instr(i)
      @e.emit("#{i.op.to_s} #{i.args[0]}")
    end

    def pp_simple_instr(i)
      str = "#{i.op.to_s}"

      if has_args?(i)
        args = i.args.map do |a|
          numeric?(a) ? a : "$#{@strings[a]}"
        end

        str += " #{args.join(' ')}"
      end

      @e.emit(str)
    end
  end

  #--------------------------------

  # The virtual machine has a set of methods that represent an
  # individual instruction.  Some core instructions, that control
  # program logic, will be common to all implementations.  Others
  # are expected to be overridden.
  class VirtualMachine
    attr_reader :fail_flag, :impl

    def initialize(impl)
      @impl = impl
    end

    def run(program, entry_point)
      @pc = entry_point
      @return_stack = Array.new
      @fail_flag = false

      catch(:done) do
        loop do
          instr = program[@pc]
          method = "instr_#{instr.op.to_s}"
          send(method, *instr.args)
        end
      end
    end

    private
    def instr_jump(addr)
      @pc = addr
    end

    def instr_jump_on_fail(addr)
      if @fail_flag
        @pc = addr
      end
    end

    def instr_clear_fail(addr)
      @fail_flag = false
    end

    def instr_noop
    end

    def instr_label(l)
    end

    def instr_terminate(v)
      throw(:done, v)
    end

    def method_missing(method, *args)
      m = /^instr_(.+)/.match(method.to_s)
      if m
        @impl.send(method, *args)
      else
        super
      end
    end
  end

  #--------------------------------

  # factory methods for building instructions
  def self.def_instr(method, arg_class = nil)
    if arg_class.nil?
      define_method(method) do |*args|
        Instruction.new(method, *args)
      end
    else
      define_method(method) do |*args|
        raise "Incorrect nr of arguments for #{method} instruction" unless args.length == 1
        raise "Incorrect class type for argument" unless args[0].class == arg_class
        Instruction.new(method, *args)
      end
    end
  end

  def_instr(:create)
  def_instr(:remove)
  def_instr(:suspend)
  def_instr(:resume)
  def_instr(:load)
  def_instr(:clear)
  def_instr(:message)
  def_instr(:wait)
  def_instr(:jump, Symbol)
  def_instr(:jump_on_fail, Symbol)
  def_instr(:clear_fail)
  def_instr(:noop)
  def_instr(:label, Symbol)
  def_instr(:terminate)
end

#----------------------------------------------------------------
