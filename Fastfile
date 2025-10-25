# Fastfile for Atlas iOS App
# https://docs.fastlane.tools

default_platform(:ios)

platform :ios do
  # Variables
  scheme = "Atlas"
  workspace = "Atlas.xcworkspace"
  project = "Atlas.xcodeproj"

  before_all do
    ensure_git_status_clean
  end

  desc "Run all tests"
  lane :test do
    scan(
      scheme: scheme,
      device: "iPhone 15 Pro",
      code_coverage: true,
      output_directory: "./fastlane/test_output",
      clean: true
    )
  end

  desc "Run SwiftLint"
  lane :lint do
    swiftlint(
      mode: :lint,
      config_file: ".swiftlint.yml",
      strict: true,
      reporter: "html",
      output_file: "./fastlane/swiftlint-results.html"
    )
  end

  desc "Build for development"
  lane :build_dev do
    build_app(
      scheme: scheme,
      configuration: "Debug",
      output_directory: "./build",
      clean: true,
      export_method: "development"
    )
  end

  desc "Build for testing"
  lane :build_test do
    scan(
      scheme: scheme,
      build_for_testing: true,
      device: "iPhone 15 Pro"
    )
  end

  desc "Run tests without building"
  lane :test_without_build do
    scan(
      scheme: scheme,
      test_without_building: true,
      device: "iPhone 15 Pro"
    )
  end

  desc "Build and deploy to TestFlight"
  lane :beta do
    # Increment build number
    increment_build_number(
      xcodeproj: project
    )

    # Build the app
    build_app(
      scheme: scheme,
      configuration: "Release",
      output_directory: "./build",
      clean: true,
      export_method: "app-store",
      export_options: {
        provisioningProfiles: {
          "com.atlasapp.atlas" => "Atlas AppStore"
        }
      }
    )

    # Upload to TestFlight
    upload_to_testflight(
      skip_submission: false,
      skip_waiting_for_build_processing: false,
      distribute_external: true,
      groups: ["Beta Testers"],
      notify_external_testers: true,
      changelog: "Bug fixes and performance improvements"
    )

    # Commit version bump
    commit_version_bump(
      message: "Version bump for TestFlight",
      xcodeproj: project
    )

    # Tag the release
    add_git_tag(
      tag: "testflight/#{get_version_number}/#{get_build_number}"
    )

    # Push changes
    push_to_git_remote
  end

  desc "Deploy to App Store"
  lane :release do
    # Ensure on main branch
    ensure_git_branch(branch: "main")

    # Increment version number
    increment_version_number(
      xcodeproj: project,
      bump_type: "patch"
    )

    # Increment build number
    increment_build_number(
      xcodeproj: project
    )

    # Build the app
    build_app(
      scheme: scheme,
      configuration: "Release",
      output_directory: "./build",
      clean: true,
      export_method: "app-store"
    )

    # Upload to App Store
    upload_to_app_store(
      force: true,
      submit_for_review: true,
      automatic_release: false,
      submission_information: {
        add_id_info_uses_idfa: false
      }
    )

    # Commit version bump
    commit_version_bump(
      message: "Release version #{get_version_number}",
      xcodeproj: project
    )

    # Tag the release
    add_git_tag(
      tag: "v#{get_version_number}"
    )

    # Push changes
    push_to_git_remote
  end

  desc "Take screenshots"
  lane :screenshots do
    capture_screenshots(
      scheme: scheme,
      devices: [
        "iPhone 15 Pro Max",
        "iPhone 15 Pro",
        "iPhone SE (3rd generation)",
        "iPad Pro (12.9-inch) (6th generation)"
      ],
      languages: ["en-US"],
      output_directory: "./fastlane/screenshots",
      clear_previous_screenshots: true
    )
  end

  desc "Generate code coverage report"
  lane :coverage do
    scan(
      scheme: scheme,
      code_coverage: true,
      output_directory: "./fastlane/test_output"
    )

    slather(
      scheme: scheme,
      proj: project,
      output_directory: "./fastlane/coverage",
      html: true,
      show: true
    )
  end

  desc "Run security checks"
  lane :security do
    # Check for sensitive data
    sh("grep -r 'api_key\\|password\\|secret' ../Sources/ || true")

    # Validate entitlements
    sh("plutil -lint ../Atlas.entitlements")

    # Check for hardcoded URLs
    sh("grep -r 'http://' ../Sources/ || true")
  end

  desc "Bump patch version"
  lane :bump_patch do
    increment_version_number(
      xcodeproj: project,
      bump_type: "patch"
    )
    commit_version_bump(
      message: "Bump patch version",
      xcodeproj: project
    )
  end

  desc "Bump minor version"
  lane :bump_minor do
    increment_version_number(
      xcodeproj: project,
      bump_type: "minor"
    )
    commit_version_bump(
      message: "Bump minor version",
      xcodeproj: project
    )
  end

  desc "Bump major version"
  lane :bump_major do
    increment_version_number(
      xcodeproj: project,
      bump_type: "major"
    )
    commit_version_bump(
      message: "Bump major version",
      xcodeproj: project
    )
  end

  desc "Clean build artifacts"
  lane :clean do
    clean_build_artifacts
    clear_derived_data
  end

  desc "Setup development environment"
  lane :setup do
    # Install dependencies
    cocoapods(
      clean_install: true,
      podfile: "./Podfile"
    ) if File.exist?("./Podfile")

    # Install certificates
    match(
      type: "development",
      readonly: true
    )

    # Install SwiftLint if not present
    sh("which swiftlint || brew install swiftlint")
  end

  desc "Refresh provisioning profiles"
  lane :refresh_profiles do
    match(
      type: "development",
      force_for_new_devices: true
    )

    match(
      type: "appstore",
      force_for_new_devices: true
    )
  end

  # Error handling
  error do |lane, exception|
    notification(
      title: "Fastlane Error",
      message: "#{lane} failed: #{exception.message}"
    )
  end

  after_all do |lane|
    notification(
      title: "Fastlane Success",
      message: "#{lane} completed successfully"
    )
  end
end
