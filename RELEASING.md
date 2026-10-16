# Releasing xFractal

xFractal ships only through Apple: the iPhone/iPad app (`xFractal-iOS`) and the Mac app (`xFractal-MAS`) go to
TestFlight first, then to the App Store. Both targets share the bundle ID of the original 2008 App Store app,
`ch.arizonasoftware.xfractal`, so iPhone, iPad and Mac are one universal purchase on the same listing.

Nothing is archived, signed or uploaded from a local Mac: Xcode Cloud archives both apps.

## 1. TestFlight (`/testflight`)

The `/testflight` skill (`.claude/skills/testflight/SKILL.md`) is the only path to TestFlight. In short:

- the version lives in `CFBundleShortVersionString` of both `xFractal/Info-iOS.plist` and `xFractal/Info-MAS.plist`
  (always the same value, above the last 2008-era App Store release, 1.6);
- the macOS logic tests must pass (see "Running the tests" in `AGENTS.md`);
- the tester notes go in `TestFlight/WhatToTest.en-US.txt`;
- pushing `main` to the `testflight` branch makes Xcode Cloud archive both apps (`Archive - iOS`,
  `Archive - macOS`) and hand them to the internal testers.

Xcode Cloud numbers the builds; `CFBundleVersion` is never bumped by hand. `ci_scripts/ci_post_clone.sh` generates the
git-ignored `xFractal.xcodeproj` with XcodeGen and writes the signing team from `$CI_TEAM_ID`.

## 2. App Store

Once a TestFlight build has been checked on iPhone, iPad and Mac, submit that build for review in App Store Connect
(version, What's New, screenshots). When the version is released, tag the commit it was built from:

```sh
git tag -a v<version> -m "xFractal <version>"
git push origin v<version>
```

`/testflight` makes no tag; the App Store release does.

`xFractal/PrivacyInfo.xcprivacy` declares the one required-reason API the app uses (`UserDefaults`, reason `CA92.1`).
Update it if new required-reason APIs are added.

## The frozen appcast (`docs/appcast.xml`)

Version 1.0 of the Mac app was also published as a direct-download DMG (the `v1.0` tag and its GitHub release) that
updated itself with Sparkle from `https://jean-bovet.github.io/xFractal/appcast.xml`. The DMG and Sparkle are gone;
the Mac app now ships only through the Mac App Store.

`docs/appcast.xml` stays published exactly as it is: installed 1.0 copies keep checking it quietly, find no newer
version and show nothing. Do not edit it, add items to it or delete it: those copies must keep finding a valid feed with
nothing newer in it. Users of the DMG move to the App Store by installing the app from there.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| A Mac export fails with "Copy failed" and the distribution log shows `rsync … --extended-attributes: unknown option` | A Homebrew `rsync` is first on `PATH`; run the export with `PATH=/usr/bin:/bin:/usr/sbin:/sbin`. |
| `cannot execute tool 'metal' due to missing Metal Toolchain` | Run `xcodebuild -downloadComponent MetalToolchain` (`ci_post_clone.sh` does it on Xcode Cloud). |
