# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'polidea/ci/version'

Gem::Specification.new do |spec|
  spec.name          = "polidea-ci"
  spec.version       = Polidea::Ci::VERSION
  spec.authors       = ["Kamil Trzcinski"]
  spec.email         = ["kamil.trzcinski@polidea.com"]
  spec.summary       = %q{Write a short summary. Required.}
  spec.description   = %q{Write a longer description. Optional.}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"

  # spec.add_dependency 'thor'
  # spec.add_dependency 'addressable'
  # spec.add_dependency 'activesupport'
  # spec.add_dependency 'childprocess'
  # spec.add_dependency 'travis-yaml'#, github: 'travis-ci/travis-yaml'
  # spec.add_dependency 'travis-build'#, github: 'ayufan/travis-yaml'
end
