# frozen_string_literal: true

require_relative 'lib/active_storage/storj/version'

Gem::Specification.new do |spec|
  spec.name        = 'activestorage-storj'
  spec.version     = ActiveStorage::Storj::VERSION
  spec.authors     = ['Your Data Inc']
  spec.homepage    = 'https://github.com/Your-Data/activestorage-storj'
  spec.summary     = 'Storj Cloud Storage support for ActiveStorage in Rails'
  spec.description = 'Providing Storj Cloud Storage support for ActiveStorage in Rails'
  spec.license     = 'MIT'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{app,config,db,lib}/**/*', 'LICENSE', 'Rakefile', 'README.md']
  end

  spec.add_runtime_dependency 'rails', '~> 6.1', '>= 6.1.7'
  spec.add_runtime_dependency 'uplink-ruby', '~> 1.0'
end
