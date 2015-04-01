BILAudioIO
=================

### Dependency
* None

### Require Framework
* `AudioToolbox.framework`
* `AVFoundation.framework` (iOS only)
* `AudioUnit.framework` (OSX only)

# CocoaPods

### How to pass `pod lib lint`
```sh
pod lib lint --allow-warnings --sources='git@github.com:Beatrobo/CocoaPods-Specs.git,https://github.com/CocoaPods/Specs'
```

### How to push private pods
```sh
pod repo push --allow-warnings beatrobo *.podspec
```

# Description

BIL is "Beatrobo Inc Library" prefix.

PlugAir などで使われている SoftModem から切り出した Audio I/O 部分。
