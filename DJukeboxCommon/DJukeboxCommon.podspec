# coding: utf-8
#

Pod::Spec.new do |s|

  s.name         = "DJukeboxCommon"
  s.version      = "0.0.1"
  s.summary      = "DJukebox common code"

  s.description  = <<-DESC
  This is DJukebox common code
                   DESC

  s.homepage     = "http://theory.org"
  s.license      = "GPL"

  s.author       = { "" => "" }
  s.platforms    = { :osx =>  "10.15", :ios => "13.0" }

  s.source       = { :git => "git@github.com:Automatic/swift-core.git", :branch => "develop" }
  s.source_files  = "Sources/**/*.{swift}"

  s.pod_target_xcconfig = { 'SWIFT_VERSION' => 5 }

end
