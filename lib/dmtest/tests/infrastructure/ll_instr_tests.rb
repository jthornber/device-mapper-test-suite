require 'dmtest/device-mapper/ll_instr'

#----------------------------------------------------------------

class LLInstrTests < Test::Unit::TestCase
  include DM::LowLevel

  def test_instruction
    i = Instruction.new(:blip, 1, 2, 3, 4)
    assert_equal(:blip, i.op)
    assert_equal(1, i[0])
    assert_equal(2, i[1])
    assert_equal([1, 2, 3, 4], i.args)

    args = Array.new
    i.each do |n|
      args << n
    end

    assert_equal([1, 2, 3, 4], args)
  end

  def method_takes_symbol(method)
    send(method, :foo)

    assert_raise(RuntimeError) do
      send(method, 234)
    end

    assert_raise(RuntimeError) do
      send(method, 'lksjdfs')
    end

    assert_raise(RuntimeError) do
      send(method)
    end
  end

  def test_symbol_instrs
    method_takes_symbol(:label)
    method_takes_symbol(:jump)
    method_takes_symbol(:jump_on_fail)
  end

  EXPECTED = <<EOF
.string 0
            a short string

.string 1
            foo456

.string 3
            lksjdf

.string 4
            sdlf

.string 2
            sldkj

.main
    create $0
    remove 0 1 2

.foo456
    suspend $2 $3
    resume 0 $4 56
    load 345
    clear
    message
    wait
    jump foo456
    jump_on_fail foo456
    clear_fail
    noop
EOF

  def test_formatter
    instrs = [create('a short string'),
              remove(0, 1, 2),
              label(:foo456),
              suspend('sldkj', 'lksjdf'),
              resume(0, 'sdlf', 56),
              load(345),
              clear,
              message,
              wait,
              jump(:foo456),
              jump_on_fail(:foo456),
              clear_fail,
              noop
             ]

    f = ProgramFormatter.new(instrs)

    io = StringIO.new
    f.format(io)
    assert_equal(EXPECTED, io.string)
  end

  #--------------------------------

  class LoggingImpl
    attr_reader :calls

    def initialize
      @calls = Array.new
    end

    def method_missing(method, *args)
      STDERR.puts "in method missing #{method} #{args}"

      m = /^instr_(.+)/.match(method.to_s)
      if m
        @calls << DM::LowLevel::Instruction.new(m[1].intern, *args)
      else
        super
      end
    end
  end
  
  def test_vm
    instrs = [create('a short string')
             ]

    impl = LoggingImpl.new
    vm = VirtualMachine.new(impl)

    vm.run([create('lskdjlsj'),
            terminate(0)], 0)

    pp impl.calls
  end
end

#----------------------------------------------------------------
