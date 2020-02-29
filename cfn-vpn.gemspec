
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "cfnvpn/version"

Gem::Specification.new do |spec|
  spec.name          = "cfn-vpn"
  spec.version       = CfnVpn::VERSION
  spec.authors       = ["Guslington"]
  spec.email         = ["guslington@gmail.com"]

  spec.summary       = %q{creates and manages resources for the aws client vpn}
  spec.description   = %q{creates and manages resources for the aws client vpn}
  spec.homepage      = "https://github.com/base2services/aws-client-vpn"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = 'https://rubygems.org'

    spec.metadata["homepage_uri"] = spec.homepage
    spec.metadata["source_code_uri"] = "https://github.com/base2services/aws-client-vpn"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 0.20"
  spec.add_dependency "terminal-table", '~> 1', '<2'
  spec.add_dependency 'cfhighlander', '~> 0.9', '<1'
  spec.add_dependency 'netaddr', '2.0.4'
  spec.add_runtime_dependency 'aws-sdk-ec2', '~> 1.95', '<2'
  spec.add_runtime_dependency 'aws-sdk-acm', '~> 1', '<2'
  spec.add_runtime_dependency 'aws-sdk-s3', '~> 1', '<2'
  spec.add_runtime_dependency 'aws-sdk-cloudformation', '~> 1', '<2'

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
