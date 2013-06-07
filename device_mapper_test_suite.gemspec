# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'dmtest/version'

Gem::Specification.new do |spec|
  spec.name          = "device_mapper_test_suite"
  spec.version       = DMTest::VERSION
  spec.authors       = ["Joe Thornber"]
  spec.email         = ["ejt@redhat.com"]
  spec.description   = %q{Functional tests for device-mapper targets}
  spec.summary       = %q{Functional tests for device-mapper targets}
  spec.homepage      = ""
  spec.license       = "GPL"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "test-unit", "1.2.3"
  spec.add_dependency "ejt_command_line"
  spec.add_dependency "thinp_xml"
  spec.add_dependency "rspec"
  spec.add_dependency "webrick"

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
