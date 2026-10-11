#!/bin/sh
# Xcode Cloud: generate xFractal.xcodeproj (git-ignored, built from project.yml by XcodeGen)
# and give the build its signing team without committing it (the repo is public).
# CI_TEAM_ID is provided by Xcode Cloud; Signing.xcconfig #include?s the file written here.
set -e
printf 'DEVELOPMENT_TEAM = %s\n' "$CI_TEAM_ID" > "$CI_PRIMARY_REPOSITORY_PATH/Signing.local.xcconfig"
brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate
