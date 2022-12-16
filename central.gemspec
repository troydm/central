# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'central'
  s.version     = '0.3.2'
  s.date        = '2022-02-11'
  s.summary     = 'central dotfile management'
  s.description = 'central dotfile management system'
  s.authors     = ['Dmitry Geurkov']
  s.email       = 'd.geurkov@gmail.com'
  s.files       = ['lib/central.rb']
  s.homepage    = 'https://github.com/troydm/central'
  s.license     = 'LGPL-3.0'
  s.executables << 'central'
  s.required_ruby_version = '>= 2.3'
  s.add_development_dependency 'rubyzip', '>= 2.3.2', '< 3.0'
end
