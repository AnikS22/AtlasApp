# Atlas iOS App - Xcode Project

AI-powered voice assistant iOS application built with Swift and SwiftUI.

## Quick Start

```bash
# Open project in Xcode
open AtlasApp.xcodeproj

# Or build from command line
xcodebuild -scheme Atlas -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build

# Run tests
xcodebuild test -scheme Atlas -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

## Project Files

- **Info.plist** - App configuration with privacy descriptions and capabilities
- **Atlas.entitlements** - App entitlements and permissions
- **Package.swift** - Swift Package Manager dependencies
- **.swiftlint.yml** - Code quality rules
- **ExportOptions.plist** - App Store export configuration
- **Fastfile** - Fastlane automation scripts

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+
- macOS 14.0+

## Features Configured

### Privacy Permissions
- Microphone access (voice recording)
- Speech recognition
- Camera access
- Photo library
- Location (when in use)
- Contacts, Calendar, Reminders

### Background Modes
- Audio playback
- Background fetch
- Remote notifications
- Background processing

### Security Features
- Keychain access groups
- Data protection (complete)
- App Transport Security (TLS 1.2+)
- SSL certificate pinning ready

### Cloud & Services
- iCloud (CloudKit, Documents)
- Push notifications
- Universal Links
- OAuth callbacks (atlasapp://)

## Build Configurations

### Debug
- Optimizations disabled
- Debug symbols enabled
- Testability enabled
- Fast compilation

### Release
- Whole module optimization
- Size optimization
- Debug symbols stripped
- Production ready

## CI/CD Pipeline

GitHub Actions workflow (`.github/workflows/ios-ci.yml`) includes:

- **Lint**: SwiftLint code quality checks
- **Build & Test**: Automated testing with code coverage
- **Security Scan**: Checks for hardcoded secrets
- **Release Build**: Creates IPA for distribution
- **TestFlight Deploy**: Automatic beta deployment

## Quick Commands

```bash
# Run SwiftLint
swiftlint lint --config .swiftlint.yml

# Build for testing
xcodebuild build-for-testing -scheme Atlas

# Run tests without building
xcodebuild test-without-building -scheme Atlas

# Create archive
xcodebuild archive -scheme Atlas -archivePath ./build/Atlas.xcarchive

# Export IPA
xcodebuild -exportArchive -archivePath ./build/Atlas.xcarchive \
  -exportPath ./build -exportOptionsPlist ExportOptions.plist
```

## Fastlane

```bash
# Install Fastlane
sudo gem install fastlane

# Available lanes
fastlane test              # Run tests
fastlane lint              # Run SwiftLint
fastlane beta              # Deploy to TestFlight
fastlane release           # Deploy to App Store
fastlane screenshots       # Generate screenshots
fastlane coverage          # Code coverage report
```

## Dependencies

Core packages managed via Swift Package Manager:

- **OpenAI** - AI API integration
- **Alamofire** - Networking
- **KeychainAccess** - Secure storage
- **RealmSwift** - Local database
- **Firebase** - Analytics & Crashlytics
- **Sentry** - Error tracking

Full list in `Package.swift`.

## Configuration Steps

1. **Update Team ID** in project settings
2. **Configure signing** in Signing & Capabilities
3. **Update Bundle ID** to match your app
4. **Add API keys** to secure storage (never commit!)
5. **Configure OAuth** callback URLs
6. **Set up provisioning** profiles

## Documentation

- [Xcode Setup Guide](../docs/xcode-setup.md) - Comprehensive setup instructions
- [Build & Deploy](../docs/xcode-setup.md#distribution) - Distribution guide
- [CI/CD Pipeline](../.github/workflows/ios-ci.yml) - Automation details

## Security Notes

- Never commit API keys or secrets
- Use Keychain for sensitive data
- Enable certificate pinning for production
- Review privacy descriptions before submission
- Keep provisioning profiles secure

## Troubleshooting

### Build Issues
```bash
# Clean build
xcodebuild clean -scheme Atlas

# Clear derived data
rm -rf ~/Library/Developer/Xcode/DerivedData

# Reset package cache
rm -rf .build
xcodebuild -resolvePackageDependencies
```

### Simulator Issues
```bash
# Reset all simulators
xcrun simctl shutdown all
xcrun simctl erase all
```

### Code Signing
```bash
# List signing identities
security find-identity -v -p codesigning

# Check provisioning profiles
ls ~/Library/MobileDevice/Provisioning\ Profiles/
```

## Support

- GitHub Issues: Report bugs and request features
- Documentation: Check `/docs` folder
- CI Logs: Review GitHub Actions for build issues

## License

Copyright © 2025 Atlas App. All rights reserved.

---

**Last Updated**: 2025-10-25
**Version**: 1.0.0
**Target**: iOS 17.0+
