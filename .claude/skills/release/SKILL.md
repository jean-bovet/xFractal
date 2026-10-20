---
name: release
description: Publish the xFractal build testers already have on TestFlight to the App Store — the iPhone/iPad app (xFractal-iOS) and the Mac App Store app (xFractal-MAS), one universal purchase. Use when Jean says "release", "App Store", "submit xFractal", "ship to the public". Sending a build to TestFlight is `/testflight`, not this skill.
allowed-tools: Read, Edit, Write, Bash, AskUserQuestion
---

# /release — publish the tested TestFlight build of xFractal to the App Store

- App: **xFractal**, bundle ID `ch.arizonasoftware.xfractal` (the 2008 App Store app; the rewrite
  shipped as 2.0 on iOS and the Mac, uploaded from Xcode before this skill, untagged), App Store product `xFractal-iOS` (the Xcode Cloud product, passed
  as `--app xFractal-iOS` to every `app-store` call). The Xcode Cloud product builds both apps.
- Platforms: iPhone and iPad (`xFractal-iOS`, App Store platform `IOS`, families `iphone,ipad`) and
  the Mac (`xFractal-MAS`, platform `MAC_OS`, family `mac`). They share one App Store listing (one
  universal purchase), but App Store Connect keeps **one version per platform**: every `app-store`
  step below runs once for `--platform IOS` and once for `--platform MAC_OS`, and Jean attaches and
  submits each platform's build.
- The App Store setup: `RELEASING.md`. The privacy policy page is `docs/privacy.html` (GitHub Pages).
- No `release` branch: the `v<version>` tag marks the published commit. The `v1.0` tag is older: it
  marks the Mac DMG published with Sparkle (frozen, see `RELEASING.md`), not an App Store release.

## How a release reaches the App Store

- **This skill builds nothing.** Every build comes from `/testflight`. `/release` publishes the
  commit `origin/testflight` points to — the **candidate**, the build Jean tested — even when `main`
  has moved on since; those later commits wait for the next `/testflight`.
- The version was set by `/testflight` and stays the same for every TestFlight build until this
  skill tags it. Fixing a rejected or broken candidate is therefore another `/testflight` at the same
  version, then `/release` again.
- The `app-store` tool creates the App Store version, sets What's New on every locale and configures
  the phased release. It and the `release-check` tool (§2b) live where the global working agreement
  says, and load their own credentials; never open or source them. Attaching the build and
  submitting it for review are Jean's, in App Store Connect.
- Three hard stops: the readiness audit (§2b) when it finds a problem, the notes review (§4) and App
  Review (§6). Never continue past one without an explicit answer from Jean.
- **Retired domains** (the global working agreement's list, e.g. arizona-software.ch → jean-bovet.ch)
  must appear nowhere: not in shipped files, not in any App Store URL, description or notes. Both
  checkers in §2b flag them; new pages go on the replacement domain.
- **Email addresses** (the global working agreement's contacts): the `apple-review` address only in
  the App Review contact; the `public` one everywhere public or external — support and privacy pages,
  the description, in-app text. Both checkers flag the Apple-only address where it doesn't belong.
- It runs in the main conversation — no subagent. Stop on the first failure, say which step failed
  and why, and leave the rest undone. Never fake a check that is Jean's to make.

## 1. Guards

```bash
git rev-parse --abbrev-ref HEAD                      # must be main
git status --porcelain --untracked-files=all         # must be empty
git fetch origin main testflight --tags
git rev-list --count main..origin/main               # must be 0 (main not behind)
git rev-parse origin/testflight                      # the candidate
git merge-base --is-ancestor origin/testflight main  # must succeed
```

Changes you did not make: never stash, commit, discard or include them. Name them and ask Jean.

## 2. The candidate — new, resumed or nothing

The marketing version is `CFBundleShortVersionString` in both Info plists, which must carry the same
value (`/testflight` keeps `MARKETING_VERSION` in `project.yml` equal to it):

```bash
git show <candidate>:xFractal/Info-iOS.plist | grep -A1 CFBundleShortVersionString
git show <candidate>:xFractal/Info-MAS.plist | grep -A1 CFBundleShortVersionString   # must match
```

It must be above the live App Store version (`app-store status`; 2.0 on both platforms).

Read the candidate's version, then:

```bash
git rev-parse -q --verify "v<version>^{commit}"       # the version's tag, if any
git describe --tags --abbrev=0 --match 'v*' <candidate>^   # the last release tag before it
git log --format='%h %s' <last-tag>..<candidate>      # what the App Store has not received
```

- **Tag on the candidate**: this version is already released. Report `app-store status` and stop.
- **Tag on another commit**: the candidate's version has shipped before; `/testflight` must bump
  it first. Stop.
- **No tag, range empty**: nothing to release. Stop.
- **No tag, and `git log --format=%s <candidate>..main` has `Release notes <version>`**: an earlier
  run stopped after §5. Keep those notes, re-run §6 (`prepare` is idempotent) and continue. A notes
  file without that commit is only a draft: §4 rewrites it from the range.
- Otherwise it is a **new release** of that range.

**CI.** Find the Xcode Cloud run of the candidate's commit (`xcode-cloud builds --limit 10`) and
`report` it: every action passed, including test actions on a run marked SUCCEEDED. Note its
build number for §6.

Here: `xcode-cloud builds xFractal-iOS --limit 10` and `xcode-cloud report xFractal-iOS <build number>`
(the tool's path is in the global working agreement). The run that pushing `testflight` started holds
both archives (Archive - iOS, Archive - macOS): both must have passed and uploaded.

## 2b. Readiness audit (STOP on any problem)

App Review and App Store Connect reject, or hold, a submission for things no test catches. Run both
read-only checkers. `release-check` reads the working tree, which §1 proved is `main`; when
`git diff --stat <candidate> main` touches the project, Info.plist or sources, run it in a
temporary worktree of the candidate instead (`git worktree add`, then remove it).

```bash
release-check                                                        # the repo's sources
app-store check --app xFractal-iOS --platform IOS --version <version> --families iphone,ipad
app-store check --app xFractal-iOS --platform MAC_OS --version <version> --families mac
```

`release-check` reads `project.yml`; the families and version it prints may not reflect the
plists (§2 reads the version there). The families above are xFractal's.

Each prints `PROBLEM`, `CHECK` and `ok` lines. What they cover, and what to judge in the `CHECK`s:

| Area | Watch for |
|---|---|
| Privacy manifest | Required-reason APIs (UserDefaults, file timestamps, boot time, disk space, keyboards) used without `PrivacyInfo.xcprivacy` declaring them: ITMS-91053, rejected |
| Export compliance | No `ITSAppUsesNonExemptEncryption`: every build waits on "Missing Compliance" |
| Description, keywords, promotional text | Still true of this build: an old description promising removed features (guideline 2.3), a retired domain, an old device ("iPod touch") |
| Screenshots | A set at the required size for **every** device family the build supports (a newly added iPad needs iPad screenshots); old sets that show an outdated UI |
| URLs | Support and marketing URLs on every locale, a privacy policy URL (required), all `https` and returning 200, none on a retired domain |
| Copyright | Current year |
| Age rating | Questions Apple added since the last release left unanswered block submission |
| Email addresses | App Review contact = the `apple-review` address; support pages, description and in-app text use the `public` one |
| App Review details | Contact still current; "sign-in required" off unless there is a login; notes that explain every permission (`NS…UsageDescription`) and any hidden or hard-to-reach feature |
| App Privacy label | Not readable through the API: compare it with what the build collects (permissions, SDKs, network use); an app last updated before 2020 may have none |
| Features removed since the live version | What's New (§4) must say so; the description must not still promise them |

If either checker exits non-zero, or a `CHECK` shows something false, **stop**: list each problem
with its proposed fix (code fixes follow the repo's own workflow and need a new `/testflight`;
App Store page fixes use `app-store metadata`, `age-rating` and `screenshots`; pages on the web go
on the non-retired domain), and ask Jean whether to fix them. Resume at §2 once fixed — a code fix
changes the candidate.

## 3. Questions

Ask with `AskUserQuestion`, in one call (skip what Jean already answered):

1. **Tested** — is the TestFlight build `<version> (<build>)`, commit `<candidate>`, good to
   publish? Anything but yes: stop.

2. **Screenshots** — §2b proved an iPhone 6.9", an iPad 13" and a Mac set exist; did the UI change
   enough to retake any of them (`/preview-gallery` shows the iPhone screens)?
3. **Description** — does a new feature, or a change on one platform, belong in it?
4. **Privacy policy** — does the range change what the app stores or sends, so `docs/privacy.html`
   and the App Privacy label must change?

## 4. App Store notes (STOP for review)

Read the subjects and bodies of the §2 range. Keep only what a user of the App Store version will
notice, written from their side: no ticket ids, internal names, file names or "fix for #…"; no
emoji (App Store Connect rejects some); at most 4000 characters per locale.

Four notes files, used for both platforms: `ReleaseNotes/<version>-en-US.txt` first, then its
translations `-fr-FR.txt`, `-de-DE.txt` and `-it.txt` (the app ships in English, French, German and
Italian; use the app's own words from `xFractal/Localizable.xcstrings`; French and German address the
user as *vous* / *Sie*, Italian as *tu*). Plain text: a one-line lead, then short `- ` lines;
match the previous file's tone once there is one (`app-store status` shows the live notes). Say when an
item concerns only iPhone/iPad or only the Mac.

The rewrite already shipped as 2.0, so What's New describes the changes since the live version;
`app-store status` shows its notes. The first release with the translated app (2.1) says so first:
the app is now available in French, German and Italian.

**The App Store page.** Every language's description lives in `AppStore/`, one per platform
(`description-ios-<locale>.txt`, `description-mac-<locale>.txt`, at most 4000 characters), the
keywords in `AppStore/keywords.txt` (at most 100 bytes per locale), the name and subtitle in
`AppStore/app-info.txt` (at most 30 characters each). When the range changes what a description
promises, update the English one and its translations and show them with the notes. 2.0 was
en-US only: 2.1 adds `fr-FR`, `de-DE` and `it` to the listing (§6).

Show Jean every notes file in full, with the commit list it came from, and ask for a yes or his
edits. Apply edits and show again until approved. **Do not commit before that.**

## 5. Commit the notes on `main`

Stage only the notes files (and `AppStore/` when it changed) — never `git add -A` — and end the commit message with the session's
attribution trailer:

```bash
git commit -m "Release notes <version>"
git push origin main
```

The notes commit lands after the candidate on `main`; the tag in §7 still goes on the candidate.

## 6. App Store Connect (STOP for App Review)

For each platform, `<P>` = `IOS` with `<p>` = `ios`, then `<P>` = `MAC_OS` with `<p>` = `mac`
(`N=ReleaseNotes/<version>`):

```bash
app-store status --app xFractal-iOS
app-store prepare --app xFractal-iOS --platform <P> --version <version> --notes-file $N-en-US.txt \
    --notes fr-FR=$N-fr-FR.txt --notes de-DE=$N-de-DE.txt --notes it=$N-it.txt
app-store metadata --app xFractal-iOS --platform <P> --version <version> \
    --add-locale fr-FR --add-locale de-DE --add-locale it \
    --name en-US=xFractal --name fr-FR=xFractal --name de-DE=xFractal --name it=xFractal \
    --description en-US=AppStore/description-<p>-en-US.txt --description fr-FR=AppStore/description-<p>-fr-FR.txt \
    --description de-DE=AppStore/description-<p>-de-DE.txt --description it=AppStore/description-<p>-it.txt \
    --keywords "en-US=…" --keywords "fr-FR=…" --keywords "de-DE=…" --keywords "it=…" \
    --support-url https://github.com/jean-bovet/xFractal --marketing-url https://github.com/jean-bovet/xFractal \
    --privacy-url https://jean-bovet.github.io/xFractal/privacy.html \
    --review-contact-email jean_bovet@mac.com      # the apple-review address of maestro's global/contacts.txt
app-store prepare …                      # the same prepare again: gives the added locales their What's New
app-store age-rating --app xFractal-iOS --set socialMediaAgeRestricted=false   # once (the app info is shared); 2.0 left it unanswered
app-store check --app xFractal-iOS --platform IOS --version <version> --families iphone,ipad     # must report 0 problems
app-store check --app xFractal-iOS --platform MAC_OS --version <version> --families mac         # must report 0 problems
```

`metadata` gets the keywords from `AppStore/keywords.txt` (one `--keywords` per line) and the names
from `AppStore/app-info.txt` (plus `--subtitle` once a line has one). `--add-locale` does nothing for a
locale the version already has, so the same commands serve every release; `metadata` only matters
when `AppStore/` changed or `check` reports a locale missing something. Each added locale then gets
its own screenshots (`/app-store-screenshots`: the headlines and the app in that language).

If App Store Connect refuses a step for one platform (What's New, the phased release), stop and
report the error to Jean.

Then list Jean's manual steps:

- attach build `<build>` (the candidate's, from §2) to version `<version>` and submit for review;
- confirm the App Privacy label matches the build (the API cannot read it);

- each platform separately: the iOS build to the `IOS` version, the Mac build to the `MAC_OS`
  version (both from the candidate's Xcode Cloud run), each submitted;
- screenshots retaken (§3 answer 2): upload with `app-store screenshots --app xFractal-iOS`
  (`--platform IOS`: `APP_IPHONE_67`, `APP_IPAD_PRO_3GEN_129`; `--platform MAC_OS`: `APP_DESKTOP`)
  or in App Store Connect;
- the privacy policy changed (§3 answer 4): `docs/privacy.html`, committed and pushed on `main`
  (GitHub Pages publishes it), and the App Privacy label in App Store Connect.

**Stop here** until Jean says App Review approved the version (or he released it). On a rejection
that needs a code change: land the fix, `/testflight` (same version), then `/release` again.

## 7. Ship: tag the candidate

The tag is lightweight and goes on the **candidate**, not on `HEAD`:

```bash
git tag v<version> <candidate>                    # only when §2 found no tag
git push origin v<version>
git ls-remote origin "refs/tags/v<version>"       # must print the candidate's SHA
```

No release branch. Tag only once **both** platforms are approved or released; if Jean releases one
platform first, the tag waits for the other.

## 8. Report

- the version, the candidate's sha and build number, the range that shipped, the tag;
- the notes commit;
- the manual steps still open in App Store Connect, if any;
- that the next `/testflight` bumps the version.
