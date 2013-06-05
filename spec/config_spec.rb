require 'dmtest/config'

include DMTest

#----------------------------------------------------------------

describe DMTest::Profile do
  describe "attributes" do
    before :each do
      @p = Profile.new
    end

    it "should be incomplete by default" do
      @p.should_not be_complete
    end

    it "should have a metadata_dev attr" do
      @p.metadata_dev 'foo'
      @p.metadata_dev.should == 'foo'
      @p.should_not be_complete
    end

    it "should have a data-dev attr" do
      @p.data_dev 'foo'
      @p.data_dev.should == 'foo'
      @p.should_not be_complete
    end

    it "should be complete if both vars are set" do
      @p.metadata_dev 'foo'
      @p.data_dev 'bar'
      @p.should be_complete
    end
  end

  describe "initialize block" do
    it "should allow setting of attributes" do
      p = Profile.new do
        metadata_dev 'foo'
        data_dev 'bar'
      end

      p.metadata_dev.should == 'foo'
      p.data_dev.should == 'bar'
    end
  end
end

#--------------------------------

describe DMTest::Config do
  before :each do
    @c = DMTest::Config.new
  end

  it "should start with no profiles" do
    @c.should have(0).profiles
  end

  it "should allow the setting of profiles" do
    @c.profile(:ssd) do
      metadata_dev 'foo'
      data_dev 'bar'
    end

    p = @c.profiles[:ssd]
    p.metadata_dev.should == 'foo'
    p.data_dev.should == 'bar'
  end

  describe "default profile" do
    before :each do
      @c.profile(:ssd) do
        metadata_dev 'first'
      end

      @c.profile(:spindle) do
        data_dev 'second'
      end
    end

    it "should take the first profile as the default" do
      @c.default_profile.should == :ssd
    end

    it "should allow the default to be overridden" do
      @c.default_profile :spindle
      @c.default_profile.should == :spindle
    end
  end

  describe "initialize block" do
    c = DMTest::Config.new do
      profile :ssd do
        metadata_dev 'first'
      end

      profile :spindle do
        data_dev 'second'
      end
    end

    c.profiles.length.should == 2
    c.profiles[:ssd].metadata_dev.should == 'first'
    c.profiles[:spindle].data_dev.should == 'second'
  end
end

#----------------------------------------------------------------
