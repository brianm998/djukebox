# coding: utf-8
#

Pod::Spec.new do |s|

  s.name         = "DJukeboxClient"
  s.version      = "0.0.1"
  s.summary      = "DJukebox client code"

  s.description  = <<-DESC
  This is DJukebox common client code
                   DESC

  s.homepage     = "http://theory.org"
  s.license      = "GPL"

  s.author       = { "" => "" }
  s.platform     = :osx, "10.15"

  s.source       = { :git => "git@github.com:Automatic/swift-core.git", :branch => "develop" }
  s.source_files  = "Sources/**/*.{swift}"
  s.dependency "DJukeboxCommon"

  s.pod_target_xcconfig = { 'SWIFT_VERSION' => 5 }

end
