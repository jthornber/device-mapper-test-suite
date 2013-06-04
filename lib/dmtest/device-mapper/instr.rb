require 'set'

#----------------------------------------------------------------

# FIXME: add instructions for input and output.  Input should include
# a timeout.

module DM
  module LowLevel
    class Instruction
      attr_accessor :op, :args

      def initialize(op, args)
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

    class Program
      attr_accessor :instrs, :strings

      def initialize()
        @strings = Hash.new
        @instrs = Array.new
      end

      def add_string(str)
        # we don't bother with short strings
        if str.length < 20
          str
        else
          if @strings.has_key?(str)
            @strings[str]
          else
            key = @strings.size
            @strings[str] = key
            key
          end
        end
      end

      def append_instrs(instrs)
        @instrs.concat(instrs)
      end

      def pp
        @strings.entries.sort_by {|p| p[1]}.each do |str, key|
          puts ".string #{key}"
          str.lines.each do |l|
            puts "        #{l}"
          end
          puts
        end
        puts "\n"

        puts ".main"
        @instrs.each do |i|
          case i.op
          when :label
            puts ''
            puts ".#{i.args[0]}"

          else
            pp_instr(8, i)
          end
        end
      end

      def pp_instr(offset, i)
        indent = ' ' * offset
        case
        when [:jump_on_fail, :jump].member?(i.op)
          puts "#{indent}#{i.op.to_s} #{i.args[0]}"

        else
          args = i.args.map {|a| quote(a)}.join(' ')
          puts "#{indent}#{i.op.to_s} #{args}"
        end
      end

      def quote(str)
        (str.class == String) ? "\"#{str}\"" : str.to_s
      end
    end

    # The virtual machine has a set of methods that represent an
    # individual instruction.  Some core instructions, that control
    # program logic, will be common to all implementations.  Others are
    # expected to be overridden.
    class VirtualMachine
      attr_reader :fail_flag

      def execute(program, entry_point)
        @pc = entry_point
        @return_stack = Array.new
        @fail_flag = false
        catch(:done) do
          loop do
            instr = program[@pc]
            method = "instr_#{instr[0].to_s}"
            send(method, instr[1..-1])
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

      def instr_create(name)
        dmsetup('create', name)
      end

      def instr_remove(name)
        dmsetup('remove', name)
      end

      def instr_suspend(name)
        dmsetup('suspend', name)
      end

      def instr_resume(name)
        dmsetup('resume', name)
      end

      def instr_load(name, table)
        Utils::with_temp_file('dm_table') do |file|
          file.write(table)
          file.flush
          dmsetup('load', name, file.path)
        end
      end

      def instr_clear(name)
        dmsetup('clear', name)
      end

      def instr_message(name, offset, msg)
        dmsetup('message', name, msg)
      end

      def instr_wait(name, event_nr)
        dmsetup('wait', name, event_nr)
      end

      def instr_noop
      end

      def instr_label(l)
      end
    end

    def self.def_instr(method)
      define_method(method) do |*args|
        Instruction.new(method, args)
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
    def_instr(:jump)
    def_instr(:jump_on_fail)
    def_instr(:clear_fail)
    def_instr(:noop)
    def_instr(:label)
  end

  module MediumLevel
    # The medium level representation deals with basic blocks and
    # conditionals.  It compiles to a low-level program.  Some
    # peep-hole optimisation is done - eg, inlining, dead code
    # elimination.  This optimisation is done to improve
    # comprehensibility of the final program, rather than to improve
    # performance.

    class BasicBlock
      VALID_OPS = [:create, :remove, :suspend, :resume, :load, :clear, :message, :wait, :clear_fail, :noop]

      attr_accessor :instrs

      def initialize(instrs)
        unless instrs.all? {|e| VALID_OPS.member?(e.op)}
          raise RuntimeError, "invalid op for basic block: #{e.op}"
        end

        @instrs = instrs
      end

      def compile
        @instrs
      end
    end

    class Label
      attr_accessor :mir, :label

      @@key = 0
      def self.next_label
        l = "label_#{@@key}"
        @@key = @@key + 1

        l
      end

      def initialize(mir)
        @mir = mir
        @label = Label.next_label
      end

      def compile
        code = Array.new
        code << Instruction.new(:label, [@label])
        code.concat(@mir.compile)

        code
      end
    end

    class Cond
      attr_accessor :on_success, :on_fail

      def initialize(on_success, on_fail)
        @on_success = Label.new(on_success)
        @on_fail = Label.new(on_fail)
      end

      def compile
        out = Label.new(BasicBlock.new([]))

        code = Array.new
        code << LowLevel::jump_on_fail(@on_fail.label)
        code.concat(@on_success.compile)
        code << LowLevel::jump(out.label)

        code.concat(@on_fail.compile)
        code.concat(out.compile)

        code
      end
    end

    class Sequence
      attr_accessor :blocks

      def initialize(blocks)
        @blocks = blocks
      end

      def append(block)
        @blocks << block
      end

      def compile
        code = Array.new

        blocks.each do |b|
          code.concat(b.compile)
        end

        code
      end
    end

    def unlabel(instrs)
      instrs                    # FIXME: finish
    end

    def compile(mir)
      instrs = mir.compile

      prog = LowLevel::Program.new

      instrs.each do |i|
        i.args.map! {|a| prog.add_string(a.to_s)}
      end

      prog.append_instrs(instrs)
      prog
    end
  end

  module HighLevel
    # The high level interface is less general, instead providing
    # constructs that are more specific to our needs.


    # Associate labels with BBs
    class BBSet
      attr_accessor :blocks

      def initialize
        @key = 0
        @blocks = Hash.new
      end

      def insert(bb)
        key = "basic_block_#{@key}".intern
        @key = @key + 1
        @blocks[key] = bb
        key
      end

      def lookup(key)
        @blocks.fetch(key)
      end
    end

    class Sequence
      def initialize(instrs)
        @instrs = instrs
      end

      # Compile returns a sequence, and 2 entry points, one for exec,
      # one for undo.  Both of these instruction paths should call
      # return when they complete.
      def compile
        compiled = @instrs.map {|i| i.compile}

        prog = Array.new
        entry_points = Array.new
        compiled.each do |cc|
          code, exec_entry, undo_entry = cc
          pc = prog.size
          prog.concat(code)
          entry_points << [pc + exec_entry, pc + undo_entry]
        end

        # now we emit the error paths
        undo_entry = prog.size
        error_entries = Array.new
        (entry_points.size - 1).downto(0) do |n|
          pc = prog.size
          error_entries << pc
          prog << [:push_return, pc + 2]
          prog << [:jump, entry_points[n][1]]
        end
        error_entries << prog.size
        prog << [:return]
        error_entries.reverse!

        exec_entry = prog.size
        0.upto(entry_points.size - 1) do |n|
          pc = prog.size
          prog << [:push_return, pc + 2]
          prog << [:jump, entry_points[n][0]]
          prog << [:jump_on_fail, error_entries[n]]
        end
        prog << [:return]

        return [prog, exec_entry, undo_entry]
      end
    end

    class Alternation
      def initialize(instrs)
        @instrs = instrs
        @executed = nil
      end

      def compile
      end
    end

    class Create
      def initialize(name)
        @name = name
      end

      def compile
        [[[:create, @name],
          [:return],
          [:remove, @name],
          [:return]],
         0, 2]
      end
    end

    class Remove
      def initialize(name)
        @name = name
      end

      def compile
        [[[:remove, @name],
          [:return],
          [:fail],               # you can't undo a remove
          [:return]],
         0, 2]
      end
    end

    class Suspend
      def initialize(name)
        @name = name
      end

      def compile
        [[[:suspend, @name],
          [:return],
          [:resume, @name],
          [:return]],
         0, 2]
      end
    end

    class Resume
      def initialize(name)
        @name = name
      end

      def compile
        [[[:resume, @name],
          [:return],
          [:suspend, @name],
          [:return]],
         0, 2]
      end
    end

    class Load
      def initialize(name, table)
        @name = name
        @table = table
      end

      def compile
        [[[:load, @name, @table],
          [:return],
          [:clear, @name],
          [:return]],
         0, 2]
      end
    end

    class Clear
      def initialize(name)
        @name = name
      end

      def clear
        [[[:clear, @name],
          [:return],
          [:fail],              # unreversable
          [:return]],
         0, 2]
      end
    end

    class Message
      def initialize(name, offset, msg, reverse_msg)
        @name = name
        @offset = offset
        @msg = msg
        @reverse_msg = reverse_msg
      end

      def compile
        [[[:message, @name, @offset, @msg],
          [:return],
          [:message, @name, @offset, @reverse_msg],
          [:return]],
         0, 2]
      end
    end

    class Wait
      def initialize(name, event_nr)
        @name = name
        @event_nr = event_nr
      end

      def compile
        [[[:wait, @event_nr],
          [:return],
          [:return]],            # reversing is a no-op
         0, 2]
      end
    end
    
    #------------------------------------------------
    # A little peep-hole optimiser.  Currently inlines trivial
    # sub-routines and removes some dead code.
    #------------------------------------------------

    def inline(program)
      instrs, exec, undo = program
      window_size = 2

      0.upto(instrs.size - window_size - 1) do |pc|
        if (instrs[pc] == [:push_return, pc + 2]) && (instrs[pc + 1][0] == :jump)
          dest = instrs[pc + 1][1]

          if (![:jump, :jump_on_fail].member?(instrs[dest][0])) && (instrs[dest + 1][0] == :return)
            # we can inline
            instrs[pc] = instrs[dest]
            instrs[pc + 1] = [:noop]
          end
        end
      end

      [instrs, exec, undo]
    end

    def remove_dead_code(program)
      instrs, exec, undo = program

      destinations = Set.new
      destinations.add(exec)
      destinations.add(undo)
      0.upto(instrs.size - 1) do |i|
        if [:jump, :jump_on_fail].member?(instrs[i][0])
          destinations.add(instrs[i][1])
        end
      end

      remove = true
      0.upto(instrs.size - 1) do |i|
        if destinations.member?(i)
          remove = false
        end

        if remove
          instrs[i] = [:noop]
        else
          if [:jump, :return].member?(instrs[i][0])
            remove = true
          end
        end
      end

      [instrs, exec, undo]
    end

    def strip_duplicate_returns(program)
      instrs, exec, undo = program

      last_was_return = false
      (instrs.size - 1).downto(0) do |pc|
        if instrs[pc][0] == :return
          if last_was_return
            instrs[pc] = [:noop]
          end

          last_was_return = true
        else
          last_was_return = false
        end
      end

      [instrs, exec, undo]
    end

    def strip_noops(program)
      instrs, exec, undo = program

      # we take out noops, and adjust any addresses
      remapping = Hash.new
      new_instrs = Array.new
      0.upto(instrs.size - 1) do |pc|
        remapping[pc] = new_instrs.size

        case instrs[pc][0]
        when :noop
          # do nothing

        when :push_return
          new_instrs << [:push_return, remapping[instrs[pc][1]]]

        when :jump
          new_instrs << [:jump, remapping[instrs[pc][1]]]

        when :jump_on_fail
          new_instrs << [:jump_on_fail, remapping[instrs[pc][1]]]

        else
          new_instrs << instrs[pc]
        end
      end

      [new_instrs, remapping[exec], remapping[undo]]
    end

    def optimise(program)

      #strip_noops(
      #strip_duplicate_returns(
      # strip_noops(
      #    remove_dead_code(
            inline(program)
    end

    #------------------------------------------------

    $sequence_context = Array.new
    $sequence_context << Array.new

    def push_instr(i)
      $sequence_context.last << i
    end

    def sequence
      $sequence_context.push(Array.new)
      yield
      s = Sequence.new($sequence_context.pop)
      push_instr(s)
      s
    end

    def quote(str)
      (str.class == String) ? "\"#{str}\"" : str.to_s
    end

    def print_program(prog)
      instrs, exec, undo = prog
      puts "execute entry point: #{exec}"
      puts "undo entry point: #{undo}"

      0.upto(instrs.size - 1) do |i|
        code =  instrs[i][1..-1].map {|arg| quote(arg)}.join(' ')
        puts "#{i}\t#{instrs[i][0]} #{code}"
      end
    end
  end
end

#----------------------------------------------------------------
