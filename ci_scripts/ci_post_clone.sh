#!/bin/sh
# Xcode Cloud: generate xFractal.xcodeproj (git-ignored, built from project.yml by XcodeGen)
# and give the build its signing team without committing it (the repo is public).
# CI_TEAM_ID is provided by Xcode Cloud; Signing.xcconfig #include?s the file written here.
set -e
printf 'DEVELOPMENT_TEAM = %s\n' "$CI_TEAM_ID" > "$CI_PRIMARY_REPOSITORY_PATH/Signing.local.xcconfig"
brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate
# Shaders.metal needs the Metal Toolchain, a separate component. On Xcode Cloud it is present
# but not usable ("cannot execute tool 'metal' due to missing Metal Toolchain"), and a plain
# -downloadComponent fails with "already imported": delete it and download it again.
if ! xcrun metal --version; then
    xcodebuild -showComponent MetalToolchain || true
    xcodebuild -deleteComponent MetalToolchain || true
    xcodebuild -downloadComponent MetalToolchain
    xcodebuild -showComponent MetalToolchain || true
    xcrun metal --version
fi
