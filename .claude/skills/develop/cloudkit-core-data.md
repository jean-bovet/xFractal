# CloudKit-shaped Core Data — plan and review checklist

Companion to `/develop` for a repo on Core Data + `NSPersistentCloudKitContainer`. For any change that
touches the model, persistence, sync or sharing. The repo's invariants win; this list makes them
concrete. Plans cover every item that applies (holds / at risk and how it is held), and the Codex
review prompt gets this file with the invariants.

## Model
- Every attribute is optional or has a default; every relationship is optional and has an inverse.
- No uniqueness constraints — duplicates are resolved **on read**, never by a constraint.
- No `Deny` delete rule, no `Undefined` or `ObjectID` attribute types, no derived attributes.
- No model-level validation (min/max, regex, `validateForInsert/Delete`) on synced entities: a record
  from another device that fails validation stalls the import for everyone.

## Schema evolution
- The Production CloudKit schema is **additive only**: no renames, removals, type or cardinality
  changes. A rename is a new optional field plus a read-time fallback.
- Deploy the Production schema *before* the build that needs it; the committed Development export
  stays verbatim.
- An older build on another device must keep working with records written by the new one.

## Merging and history
<!-- repo-specific: merge-policy -->
- Keep the repo's merge policy (`mergeByPropertyObjectTrump`, per-field last writer wins). Never
  switch to store-trump or add per-context policies to "fix" a conflict — it silently changes who wins.
<!-- /repo-specific -->
- Never delete persistent history: `NSPersistentCloudKitContainer` mirrors from it, and purging what
  it has not exported forces a reset. No second merge pipeline next to the container's own.

## Contexts and writes
- Pass `NSManagedObjectID` between contexts, never `NSManagedObject`.
- No `NSBatchUpdateRequest` / `NSBatchDeleteRequest` on synced entities (they skip validation and
  delete rules and bypass the normal change flow); write-once entities are never updated in place.

## Sharing
<!-- repo-specific: sharing -->
- Participants, zones and authorization stay where the design puts them (e.g. "one `CKShare`, a repo
  invariant"). Advice that ignores sharing is incomplete — check the share path for every change.
<!-- /repo-specific -->

<!-- repo-specific: reading -->
Optional `## Reading` section: the repo's readers that every new entity must flow through (the live UI
reader included, not only the test-covered one), and which tests or previews actually cover each.
<!-- /repo-specific -->

## Environments
Every CloudKit app separates its environments by build configuration (the CloudKit environments
standard). A change holds it, and never weakens it:
- **Debug** runs as `<id>.debug` (its own App Group, display name "X β") on **Development** iCloud;
  **Production** (scheme "X (Production)", Debug compiler, no `DEBUG` condition) and **Release** run
  as `<id>` on **Production**. The environment comes from the entitlements, filled from build
  settings (`APP_ICLOUD_ENVIRONMENT`, `APP_APS_ENVIRONMENT`), never from a runtime switch.
- Code that names the bundle ID or the App Group reads it from the Info.plist or a build setting,
  never a literal. A new extension target follows its app (`.debug` suffix, same environment).
- The environment banner (orange "Development iCloud", green "Production iCloud · Xcode") is
  compiled in only under `CLOUDKIT_DEVELOPMENT || CLOUDKIT_PRODUCTION_XCODE`, call sites included;
  never in Release, hidden in screenshot and gallery modes.
- The schema is pushed to Development only from a Debug build; nothing reachable in Production or
  Release initialises or deploys a schema.
- A repo not yet on the standard: a change that touches identities, entitlements or schemes moves
  toward it (the doc's status table says what is owed), never further away.

## Recovery — never on a device with live data
- Never "delete and reinstall", reset the store, or create a new container to clear a sync error.
- Never ⌘R a Debug build that pushes schema onto a device holding real data.

## Diagnostics
- Launch arguments: `-com.apple.CoreData.CloudKitDebug 1`, `-com.apple.CoreData.MigrationDebug 1`.
- Observe `NSPersistentCloudKitContainer.eventChangedNotification` for setup / import / export errors.
- `log stream --predicate 'process == "cloudd" OR process == "apsd"'` while reproducing.
- Tests share one `NSManagedObjectModel` instance; a fresh model per container causes
  "Failed to find a unique match for an NSEntityDescription".
- `willSave` must not dirty the object again (save loop); `prepareForDeletion` must not save.
