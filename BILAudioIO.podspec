Pod::Spec.new do |s|
  s.name                  = "BILAudioIO"
  s.version               = "0.1"
  s.summary               = "Abstract Audio I/O for iOS and OSX"
  s.author                = { "Yusuke SUGAMIYA" => "yusuke.dnpp@gmail.com" }
  s.homepage              = "https://github.com/Beatrobo/BILAudioIO"
  s.source                = { :git => "git@github.com:Beatrobo/BILAudioIO.git", :tag => "#{s.version}" }
  s.source_files          = 'BILAudioIO/**/*.{h,m}'
  s.ios.source_files      = 'BILAudioIO/**/*.{h,m}'
  s.osx.source_files      = 'BILAudioIO/**/*.{h,m}'
  s.ios.deployment_target = '6.0'
  s.osx.deployment_target = '10.9'
  s.requires_arc          = true
  
  s.frameworks            = 'AudioToolbox'
  s.ios.framework         = 'AVFoundation'
  s.osx.framework         = 'AudioUnit'
  
  s.license = {
   :type => "Beatrobo Inc Library",
   :text => ""
  }
end
