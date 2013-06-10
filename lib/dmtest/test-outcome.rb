#----------------------------------------------------------------

def mangle(txt)
  txt.gsub(/\s+/, '_').gsub(/[(]/, '_').gsub(/[)]/, '')
end

class TestOutcome
  attr_accessor :suite, :name, :log_file, :time

  def initialize(s, n, t = nil)
    @suite = s
    @name = n
    @log_file = "#{mangle(s)}_#{mangle(n)}.log"
    @time = t || Time.now
    @pass = true
  end

  def add_fault(f)
    @pass = false
  end

  def pass?
    @pass
  end

  def get_binding
    binding
  end
end

#----------------------------------------------------------------
