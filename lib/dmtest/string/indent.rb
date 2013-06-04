#----------------------------------------------------------------

module StringUtils
  class Emitter
    def initialize(out, step = 8)
      @out = out
      @step = step
      @indent = 0
    end

    def indent
      @indent += @step

      begin
        yield
      ensure
        @indent -= @step
      end
    end

    def undent
      raise 'undent called too often' if @indent < @step

      @indent -= @step

      begin
        yield
      ensure
        @indent += @step
      end
    end

    def emit(str = '')
      @out.puts "#{' ' * @indent}#{str}"
    end
  end
end

#----------------------------------------------------------------
