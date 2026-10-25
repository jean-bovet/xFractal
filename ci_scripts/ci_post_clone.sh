#!/bin/sh
# Xcode Cloud: give the build its signing team without committing it (the repo is public).
# CI_TEAM_ID is provided by Xcode Cloud; Config/Signing.xcconfig #include?s the file written here.
set -e
printf 'DEVELOPMENT_TEAM = %s\n' "$CI_TEAM_ID" > "$CI_PRIMARY_REPOSITORY_PATH/Signing.local.xcconfig"
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
