require 'device-mapper/ml_instr'

#----------------------------------------------------------------

module DM::HighLevel
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

#----------------------------------------------------------------
