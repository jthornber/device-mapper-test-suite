# Edit this file to add your setup

module DMTest
  class Profile
    def metadata_dev(value = nil)
      @metadata_dev = value unless value.nil?
      @metadata_dev
    end

    def data_dev(value = nil)
      @data_dev = value unless value.nil?
      @data_dev
    end

    def initialize(&block)
      self.instance_eval(&block) if block
    end

    def complete?
      !(@metadata_dev.nil? || @data_dev.nil?)
    end
  end

  class Config
    attr_reader :profiles

    def initialize(&block)
      @profiles = {}
      @default_test_scale = :normal
      self.instance_eval(&block) if block
    end

    def profile(sym, &block)
      p = Profile.new(&block)

      if @default_profile.nil?
        @default_profile = sym
      end

      @profiles[sym] = p
    end

    def default_profile(sym = nil)
      @default_profile = sym unless sym.nil?
      @default_profile
    end

    def default_test_scale(sym = nil)
      @default_test_scale = sym unless sym.nil?
      @default_test_scale
    end
  end
end
