source 'https://cdn.cocoapods.org/'

platform :ios, '17.0'
use_frameworks!
inhibit_all_warnings!

target 'ddrcast' do
  # Official Google Cast iOS Sender SDK. Speaks the Cast V2 protocol to
  # devices on the local network (mDNS `_googlecast._tcp` + TLS port 8009)
  # and loads media on the Default Media Receiver (app ID CC1AD845).
  pod 'google-cast-sdk', '~> 4.8.6'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['ENABLE_BITCODE'] = 'NO'
    end
  end
end
