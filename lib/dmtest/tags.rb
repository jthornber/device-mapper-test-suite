# Allows the tagging of methods with a list of arbitrary symbols

module Tags
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def ensure_vars
      @tags = Hash.new if @tags.nil?
      @current_tags = [] if @current_tags.nil?
    end

    def tag(*syms)
      @current_tags = syms
    end

    def method_added(method)
      if method.to_s =~ /^test_/
        ensure_vars
        @tags[method] = @current_tags
      end
    end

    def get_tags(method)
      ensure_vars
      @tags[method]
    end
  end
end
