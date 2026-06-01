require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

Pod::Spec.new do |s|
  s.name           = 'NeomoviesCore'
  s.version        = package['version']
  s.summary        = 'Collaps parser native module'
  s.description    = 'Native iOS module for parsing Collaps catalog and rewriting HLS/DASH manifests'
  s.license        = { :type => 'Apache 2.0' }
  s.authors        = { 'Neo Open Source' => 'fenixoffc@gmail.com' }
  s.homepage       = 'https://git.disroot.org/Neo'
  s.platforms      = { :ios => '15.1', :tvos => '15.1' }
  s.swift_version  = '5.4'
  s.source         = { :git => 'https://git.disroot.org/Neo/neomovies-mobile.git', :tag => "v#{s.version}" }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  # Swift sources
  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
end
