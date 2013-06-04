require 'device-mapper/ll_instr'

#----------------------------------------------------------------

module DM::MediumLevel
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

#----------------------------------------------------------------
