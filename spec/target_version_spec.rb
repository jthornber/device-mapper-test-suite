require 'dmtest/device-mapper/target_version'

include DM

#----------------------------------------------------------------

describe DM::TargetVersion do
  it "should fail with badly formed strings" do
    ['foov1.2.3', 'v1.2.3foo', 'v1.2.', 'v1.2', 'v1.', 'v..', 'v.',
      'vone.two.three', 'v1.2.three', 'v1.two.3', 'vone.2.3', 'v1.2.3.4',
    'vee1.2.3'].each do |bad|
      expect do
        TargetVersion.new(bad)
      end.to raise_error
    end
  end

  it "should parse the correct values" do
    v = TargetVersion.new('v1.2.3')
    v.major.should == 1
    v.minor.should == 2
    v.patch.should == 3
  end

  it "should return FALSE if versions do not match" do
    v = TargetVersion.new('v1.2.3')
    v.should_not == TargetVersion.new('v1.2.4')
    v.should_not == TargetVersion.new('v1.4.3')
    v.should_not == TargetVersion.new('v4.2.3')
    v.should_not == TargetVersion.new('v4.4.4')
  end

  it "should return TRUE if versions do match" do
    TargetVersion.new('v1.2.3').should == TargetVersion.new('v1.2.3')
  end
end

describe 'parse_version_lines' do
  it "should fail with badly formed version line" do
    ['three words defined', 'item v1.2. 3'].each do |bad|
      expect do
        DM::parse_version_lines(bad + "\n")
      end.to raise_error
    end
  end

  it "should parse valid output" do
    input =<<EOF
cache            v1.2.1
thin-pool        v1.9.0
thin             v1.9.0
zero             v1.1.0
mirror           v1.13.2
snapshot-merge   v1.2.0
snapshot-origin  v1.8.1
snapshot         v1.11.1
multipath        v1.5.1
striped          v1.5.1
linear           v1.2.1
  spaces_before v1.2.3
spaces_after v1.2.3  
error            v1.2.0
EOF

    vs = DM::parse_version_lines(input)

    vs['cache'].should == TargetVersion.new('v1.2.1')
    vs['error'].should == TargetVersion.new('v1.2.0')
  end
end

#----------------------------------------------------------------
