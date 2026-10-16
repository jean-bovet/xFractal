---
name: testflight
description: Ship main to TestFlight through Xcode Cloud — the iPhone/iPad app (xFractal-iOS) and the Mac App Store app (xFractal-MAS) for the internal testers. Use when the user asks for a TestFlight build, to ship or push to TestFlight, or to send a build to testers.
argument-hint: "[version, e.g. 2.1 — optional; asked when omitted]"
allowed-tools: Read, Edit, Write, Bash, AskUserQuestion
---

# /testflight — ship main to TestFlight

Xcode Cloud (product `xFractal-iOS`) builds both App Store apps from this repo and hands them to
the internal TestFlight testers: `xFractal-iOS` (iPhone/iPad) and `xFractal-MAS` (Mac App Store).
Both share the bundle ID of the 2008 App Store app, `ch.arizonasoftware.xfractal`; they are the only
apps this repo ships.
`$ARGUMENTS` is the version to ship, when given (§4).

Facts this skill relies on:

- A push to `main` runs a build-only workflow (Build - iOS, Build - macOS). A push to `testflight`
  runs the archive workflow (Archive - iOS, Archive - macOS) and its "TestFlight Internal Testing"
  actions.
- `xFractal.xcodeproj` is checked in; `ci_scripts/ci_post_clone.sh` writes `Signing.local.xcconfig`
  from `$CI_TEAM_ID` and makes sure the Metal Toolchain runs.
- Xcode Cloud reads tester notes from `TestFlight/WhatToTest.en-US.txt`.
- No git tag: this skill makes none; the App Store release tags `v<version>` (RELEASING.md).

## How a build reaches TestFlight

- Xcode Cloud archives and uploads whatever the `testflight` branch points to, and takes the
  "What to Test" text from the notes files as they are at that commit. Nothing is archived,
  exported or uploaded from this Mac.
- Xcode Cloud numbers the build. `CFBundleVersion` in `xFractal/Info-iOS.plist` and
  `xFractal/Info-MAS.plist` is never bumped (Xcode Cloud replaces it), and a build number is never
  predicted: failed or retried builds consume numbers. Uploads need a build number above every
  earlier upload of this bundle ID (manual uploads reached 204), so Xcode Cloud's next build number
  must be set above that in App Store Connect ▸ Xcode Cloud ▸ Settings.
- **This skill is the only thing that moves `testflight`**, and it only ever fast-forwards it to
  `main`. A request for a TestFlight build is a request for this skill, never a hand push of the
  branch. Never `--force`.
- It runs in the main conversation: git, a few files, a check or two — no subagent.
- It ends when `testflight` is pushed (§10). Processing, the build report and the expiry reminder
  are Jean's to ask for later (§11); never wait on Xcode Cloud after the push.
- Stop on the first failure, say which step failed and why, and leave the rest undone. Never fake
  a check that is Jean's to make.

## 1. Guards

```bash
git rev-parse --abbrev-ref HEAD                      # must be main
git status --porcelain --untracked-files=all         # must be empty
git fetch origin main testflight
git rev-list --count main..origin/main               # must be 0 (main not behind)
git merge-base --is-ancestor origin/testflight main  # must succeed
```

- Changes you did not make (modified or untracked files): never stash, commit, discard or include
  them. Name them and ask Jean what to do.
- `origin/testflight` not an ancestor of `main`: something else was pushed there; Jean sorts it out
  by hand.

## 2. What goes out — new, resumed or nothing

```bash
git log --format='%h %s' origin/testflight..main
```

is exactly what the testers have not received yet. Decide which case this is now, **before any
change**, and keep the answer:

- **Resume** if `HEAD` is this skill's own release commit (§7) and `origin/testflight` is behind
  it: an earlier run committed, then stopped before the build started. Keep its version and notes,
  skip §4–§6, and continue at §7 (pushing `main` again is a no-op).
- **Nothing new** if the range is empty: say "nothing new since the last build (`<sha>`)" and stop,
  unless Jean asks for a §11 step for that build (then do only that). If he
  explicitly wants the same commit rebuilt, make no empty commit: the `xcode-cloud` tool's
  `rebuild <number>` (see §11) starts it again, or "Start Build" in App Store Connect ▸ Xcode Cloud.
- Otherwise it is a **new release** of that range.

## 3. Preconditions

No CloudKit: the app has no iCloud entitlement, so the CloudKit gate below never fires. If an
entitlement for iCloud ever appears in `xFractal-MAS.entitlements` or the iOS target, apply it.

**CloudKit Production.** TestFlight builds sync against Production, which is deployed by hand in
the CloudKit Console. When the check above finds a schema change (or cannot rule one out), ask
Jean with `AskUserQuestion` whether the Production deploy is done; on anything but yes, stop. A
build that reaches a device before its schema is the one failure this skill must never automate.

Ask the version question of §4 now, in one `AskUserQuestion` call, unless `$ARGUMENTS` gave it.

## 4. Version

The version lives in `CFBundleShortVersionString` of both `xFractal/Info-iOS.plist` and
`xFractal/Info-MAS.plist`, which always carry the same value. Offer "keep <current>" and the next
minor (e.g. 2.0 → 2.1). On a bump, change both plists and `MARKETING_VERSION` in `project.yml`
(read by the release checks) together, and nothing else (not `CFBundleVersion`). It must stay above the live App Store version (2.0 on both platforms).

State the version in your first message after the answer.

## 5. Test gate

```bash
buildlock --folder "$PWD/.build/DerivedData" -- \
  xcodebuild test -project xFractal.xcodeproj -scheme xFractal-MAS -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$PWD/.build/DerivedData"
```

macOS unit tests (71), no simulator. Run `xcodegen generate` first if `project.yml` changed (and commit
the regenerated project). Must end with `** TEST SUCCEEDED **`.

Stop on failure.

## 6. What to Test

Read the subjects and bodies of the §2 range. Drop what no tester can see: docs, skills, planning,
tests, refactors, tooling, CI scripts, project and scheme churn, String Catalog housekeeping. Write
the rest from the tester's side:

- What they can do or will notice, not what was implemented. No ticket ids, no file names, no
  internal type names, no "fix for #…".
- Plain text, at most 4000 characters per file, no emoji (App Store Connect rejected a 🔒 as
  "invalid characters"; `•`, `« »` and accented letters pass).
- The What to Test file is **replaced** every build, not appended; its history is its `git log`.
- If nothing in the range is visible to a tester, write one line saying so (e.g. "No visible
  changes: build and stability work.") rather than leaving the file stale or empty.

One file, English: `TestFlight/WhatToTest.en-US.txt`, read by the internal testers on iPhone, iPad
and Mac. Bullets starting with `- `, separated by a blank line (TestFlight shows the text verbatim),
then one `Please verify: ...` sentence naming the two or three behaviors to exercise. Say when an
item concerns only iPhone/iPad or only the Mac. The one-line "no visible changes" file is a bullet
too (e.g. "- No visible changes: build and stability work.").

Show Jean every notes file in full, with the commit list it came from, and ask
(`AskUserQuestion`) for a yes or his edits. Apply edits and show again until approved. **Do not
commit before that.**

## 7. Commit and push `main`

Stage only the files this skill changed — never `git add -A` — and end the commit message with
the session's attribution trailer.

```bash
git add TestFlight/WhatToTest.en-US.txt xFractal/Info-iOS.plist xFractal/Info-MAS.plist project.yml   # the version files only on a bump
git commit -m "TestFlight <version>: <one-line summary>"
git push origin main
```

No tag: the App Store release tags `v<version>` (RELEASING.md), not this skill.

## 8. Start the build: fast-forward `testflight`

```bash
git push origin main:refs/heads/testflight
git branch -f testflight main 2>/dev/null || true   # local copy; a worktree may have it checked out
```

The push is a fast-forward by construction of §1. A refused push means the branch moved since;
that is Jean's to resolve. Never `--force`, never push anything but `main` to `testflight`.

## 9. After the build starts

Jean installs from TestFlight on iPhone or iPad and on the Mac. Nothing more: submitting to the
App Store is a separate step (RELEASING.md, the `app-store` tool), done only when he asks.

## 10. Report — and stop

The skill is **done once `testflight` is pushed**. Do not wait for Xcode Cloud: no polling, no
background watcher, no "still running" check-ins. Report right away:

- the release commit's sha, the range that went out, the version;
- that pushing `testflight` started the archive, and where to follow it: App Store Connect ▸ the
  app ▸ Xcode Cloud ▸ Builds shows the run and its build number (never predict it); the
  TestFlight group gets the build when processing ends, with the notes as "What to Test";
- if the CloudKit gate of §3 fired, that Jean confirmed the Production deploy;
- how to ask for §11 later ("report Xcode Cloud build <n>", "remind me about <App>'s expiry").

## 11. Later, only when Jean asks

**Build report.** Read the finished run — every action, not only the archive — with the
`xcode-cloud` tool (its path is in the global working agreement; it loads its own credentials,
never open or source them):

```bash
xcode-cloud builds xFractal-iOS --limit 3        # find the run the push started
xcode-cloud report xFractal-iOS <build number>   # warnings, errors, failed tests per action (also takes a build URL)
```

List its warnings (grouped by file) and any failed test action, even when the run says SUCCEEDED,
and offer to fix them in a follow-up commit. For a failed action, `report … --logs DIR` downloads
its logs; `ci_post_clone.log` holds the post-clone script's output. Report the iOS and the Mac
archive separately: one can upload while the other fails. A run still in progress: say so and
stop; do not wait for it.

**The 90-day expiry reminder.** A push resets nothing; only a processed build does. Once the build
has processed and reached the testers — every platform's build, when there are several — read each
build's actual expiry date, take the earliest, and ask Jean once whether to create the reminder:

```bash
osascript -e 'tell application "Reminders" to make new reminder with properties {name:"<App> <version or date> (<build>) TestFlight build expires on <earliest expiry> — run /<this skill>", remind me date:date "<earliest expiry − 10 days>"}'
```

Never guess a date from the push.
