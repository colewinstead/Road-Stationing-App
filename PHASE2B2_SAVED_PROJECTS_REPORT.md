# Phase 2B.2 — Saved Projects

## Scope and architecture

Local saved projects are implemented outside RoadStationCore in the Apple-only
`RoadStationProjects` library. SwiftData stores small metadata records; a private
copy of the original LandXML remains the authoritative engineering source.
Opening a project reads and reparses those bytes through the unchanged
`LandXMLParser`, validates the saved CRS with the existing PROJ adapter, resolves
the saved alignment identity, and publishes a coherent opened session.

No AlignmentEngine, SegmentGeometry, sampled drawing paths, calculated results,
GPS fixes or runtime UI graphs are serialized. No geometry, projection formulas,
axis/unit rules, CoreLocation quality policy or validation tolerances changed.
There is no MapKit, PDF/photo feature, account, server or cloud/iCloud sync.

The native SwiftUI root now lists saved projects with name, source filename,
alignment count, source units, saved CRS summary and last-opened date. Import
creates a saved project. Rows and project settings offer rename, source
replacement and explicitly confirmed deletion. Opening never starts location;
Field Position retains its existing explicit Start Location workflow.

## SwiftData schema

`ProjectsSchemaV1` is a VersionedSchema at 1.0.0 with one `SavedProject` model.
`ProjectsMigrationPlan` registers V1 without speculative migration stages. Future
persistent model changes require a new schema version and an appropriate stage.

| Field | Purpose |
| --- | --- |
| id | Unique, stable project UUID |
| displayName | Editable project name, separate from source filename |
| sourceFileName / sourceRelativePath | Original filename and private relative source reference |
| sourceSHA256 / sourceUpdatedAt | Exact-source traceability and last import/replacement date |
| createdAt / updatedAt / lastOpenedAt | Creation, metadata change and successful open dates |
| unitRawValue / alignmentCount | Small project-list summaries; reparsed units remain authoritative |
| confirmedEPSG / provenanceRawValue | Last successful explicit CRS confirmation |
| selectedAlignmentIdentity | Stable source identity, never an array index or parser UUID |
| modelVersion | Initial record version 1 |

Provenance uses stable machine keys `landxml`, `manual` and `catalog`, independent
of display labels. Unknown provenance is actionable rather than interpreted as
another choice. `SavedProjectRecord` is the immutable-at-boundary Sendable value
passed between the repository actor and the app. SwiftData models and contexts
remain isolated in the repository.

## File ownership and layout

```text
Application Support/RoadStation/
    projects.store                 SwiftData database and its managed sidecars
    Projects/
        <Project UUID>/
            Sources/
                <Source revision UUID>.landxml
        .Trash/
            <Project UUID>-<Deletion UUID>/   only during deletion/recovery
```

Each source revision is immutable. The database points to one current relative
path. This permits staged replacement without overwriting the working source or
requiring a filesystem/database transaction to be atomic across both systems.
Future Plans, PlanRegistration, Photos and Reports directories can belong under
the same project UUID; they are not created or implemented now. Cleanup of source
revisions preserves other directories of a referenced project. Project deletion
removes the whole owned directory.

The file actor brackets the provider read with security-scoped access, parses the
input and copies its original Data bytes using an atomic file write. It saves no
external URL or bookmark. Removing the original Files/provider document does
not affect reopening. Standard CryptoKit SHA-256 detects unexpected private
source changes; duplicate imports remain legal and get distinct project UUIDs.
Relative-path validation and symbolic-link checks prevent a corrupted source
reference from escaping the owned source layout.

## Alignment identity and CRS restoration

Selection keys prefer the existing parser's source `oID`/`id`, encoded as
`source:<base64 UTF-8 identifier>`. Without a source ID they use the exact name,
`name:<base64 UTF-8 name>`, scoped to this project. Exactly one match is required.
Source IDs survive source order and name changes. Unique-name fallback survives
reordering; a renamed name-only alignment cannot be assumed to be the same one.
Missing or duplicate identities restore no alignment and show a selection
warning. Parser-generated UUIDs are deliberately not persisted.

Imported CRS metadata alone is not a confirmation. The app persists successful
confirmation and its provenance; opening revalidates the EPSG against current
PROJ with the newly parsed project's units. A saved manual/catalog choice wins
over differing imported identification, with the difference shown in a warning.
Unavailable EPSG, geographic destination, incompatible/unknown units or unknown
provenance requires choosing and confirming a usable CRS. No replacement is
guessed. Invalid temporary picker input does not overwrite the last successful
saved confirmation. Meter, international foot and US survey foot stay distinct.

A small FieldPositionSession restoration entry point reuses existing CRS
validation while retaining provenance. It does not request permission, start
CoreLocation or calculate station/offset. The existing one-shot picker and
stale-last-known snapshot behavior remain unchanged.

## Create, replace, rename and delete safety

- **Create:** read/parse first, write a new immutable source, then commit metadata.
  Metadata failure rolls back and removes staged files. Failed parsing creates no
  project. Copy failures are reported. Deferred cleanup failures surface a notice.
- **Open:** fetch metadata, read/hash/reparse the private source, validate CRS and
  selection, then record last-opened time. Missing, unreadable, corrupted or
  unexpectedly changed sources leave the project row available for replacement
  or deletion. Metadata/store load failure does not silently create an empty
  fallback database or delete project data.
- **Rename:** commit only the display name and metadata change date; original
  filename, source path, bytes and project UUID remain unchanged.
- **Replace:** stage and parse a new immutable revision, commit the new pointer,
  source filename/date/hash/units/count, then remove the old revision. Preserve
  project UUID, display name, creation date, confirmed CRS/provenance and stable
  alignment key. Failed parsing/copy/metadata save preserves the old source and
  open session. Show a review notice and any unavailable alignment/CRS warning.
- **Delete:** require the UI's destructive confirmation. Move the entire project
  directory into same-volume quarantine, commit metadata deletion, then purge.
  Metadata failure restores the quarantine; a purge failure leaves an explicit
  cleanup notice and retry action. Missing source directories can still have
  their broken metadata row deleted.

On cold start, successful metadata load precedes reconciliation. A quarantined
project still referenced by metadata is restored; committed deletions are
purged. Unreferenced project folders and source revisions are cleaned up.
Reconciliation preflights all source references before destructive cleanup;
malformed metadata cannot authorize removing a working source. A missing
metadata database with existing owned files stops initialization and retains
files for recovery. A conflicting quarantine/current directory is reported.
These cover simulated interrupted operations, not a claim of measured power-loss
or hardware durability under every filesystem failure.

## Concurrency and app lifecycle

`ProjectRepository` uses SwiftData's `@ModelActor` serial executor. Its container
is constructed in a detached task so file access, parsing, metadata work and PROJ
validation stay off MainActor. `ProjectFileStore` owns its FileManager on its own
actor. Reentrancy guards serialize operations on the same project and prevent
cleanup while operations are staged. No unchecked Sendable or concurrency
suppressions were added.

The MainActor app model constructs the ready FieldPositionSession before
publishing one OpenedProjectSession containing metadata, geometry, validated CRS,
alignment and warnings. A loading overlay preserves an existing session while
opening; a failed operation retains it. Import errors scroll into view.

Only confirmed-CRS and alignment changes trigger metadata writes, never every GPS
callback. Writes are ordered and protected by opened-session token, source path
and sequence so old asynchronous settings cannot overwrite a replacement or
newer session. The UI reports saving, saved or retryable unsaved choices. Scene
changes drain already queued writes; persistence does not wait for app shutdown.
A source replacement/project switch stops the old runtime session only after the
new session is prepared. The project navigation destination observes the model
independently so completion, save status and renamed metadata remain current
after navigation. Cold start restores the project list, not an active GPS session.

## Performance

The deterministic performance test uses the existing real CROSSGATES XML and a
disk-backed temporary SwiftData repository. Each open reconstructs geometry;
there is no serialized geometry cache. Current Mac timings, collected alongside
simulator validation, are illustrative single-run measurements rather than
thresholds or physical-iPhone benchmarks:

| Measurement | Debug | Release |
| --- | ---: | ---: |
| Project list fetch/DTO construction | 0.263 ms | 0.180 ms |
| CROSSGATES XML parse plus SHA-256 (excluding file read) | 2.216 ms | 0.642 ms |
| Repository open (read, parse/hash, metadata save, CRS/selection readiness) | 4.562 ms | 1.948 ms |

The iOS Simulator Debug run measured list 0.229 ms, XML+hash 1.142 ms and
repository open 2.151 ms on the same real source. These are simulator timings.

Repository open timing excludes SwiftUI rendering and app-side runtime session
installation. List loading requires no LandXML parse. These sizes do not justify
a second persisted geometry format. The canonical CROSSGATES XML is also copied
into the iOS test bundle, so the real-source reparse test runs there without skips.

## Verification

Implementation and automated validation are complete. Physical-iPhone lifecycle
validation remains required.

| Check | Result |
| --- | --- |
| Root Swift Debug / Release | 157 / 157 passed |
| Apple package Debug / Release | 88 / 86 passed |
| Saved-project persistence tests | 21 passed in both configurations |
| iOS RoadStationCRSTests | **88 passed**, zero failures or skips |
| RoadStationApp UI scenarios | **8 passed** across the final full run and corrected focused Files rerun |
| RoadStationApp iOS Simulator Swift 6 build | **BUILD SUCCEEDED**, arm64 and x86_64 |
| Pinned CRS catalog check | 6,280 horizontal EPSG entries; 1,081 State Plane entries; passed |
| CROSSGATES real ORD regression | **30/30 passed**, unchanged **0.001 US survey foot** tolerance |

The 21 persistence tests cover exact original bytes, SHA-256, duplicate imports,
multiple alignments/reparse, disk cold start, all three CRS provenances,
non-first selection, source-ID/name restoration, missing/ambiguous selection,
rename, delete, replacement, unit distinctions, bad EPSG/provenance/path,
missing/corrupt/unreadable source, unavailable directory/store, missing metadata
database retention, copy/save/delete faults, rollback, orphan/quarantine recovery
and out-of-order/session/source settings guards. A separate field-position test
checks restoration never requests permission, starts GPS or transforms a fix.
Existing field-position loading/stale/out-of-order and one-shot picker tests run
unchanged alongside them.

UI tests use per-test UUID temporary storage, never the user's real project root.
The new Files-import UI test confirms CRS and a non-first alignment, terminates
and relaunches, checks restored metadata/selection, renames and relaunches again,
then tests cancel/confirm deletion and cold-start absence. Existing seven engineering/import/field/picker
UI tests remain. Rename uses a native form sheet with Save/Cancel; destructive confirmation
uses a native alert. Tests wait for asynchronous completion before checking
deleted rows, then relaunch to verify deletion persists. The lifecycle test has
a 420-second automation allowance for multiple cold launches; older UI cases
retain their 300-second allowance. This changes no engineering tolerance or
location policy. GitHub Actions discovers an available installed iPhone Simulator at run
time, retains the app build and iOS unit tests, and runs the full UI helper with
staged synthetic Files inputs. No simulator UUID is hard-coded in CI.

The final full UI run passed seven cases, including the saved-project lifecycle;
its Files case failed in the automation helper when a virtualized row had an
invalid activation frame. The helper now checks finite, visible geometry before
asking for hittability. The corrected Files-only run passed (82.293 seconds),
so all eight scenarios have passing final evidence. The earlier full bundle is
not claimed to be one clean eight-test run. The standalone final lifecycle run
also passed (143.975 seconds). Earlier attempts exposed stale destination state,
unsupported native alert identifiers, and asynchronous assertion timing; these
were corrected without removing assertions or changing calculation policy.
The real system Files browser gets up to 60 seconds for cold simulator startup.

Final logs: `core-debug.log`, `core-release.log`, `apple-debug.log`,
`apple-release.log`, `ios-crs-complete.log`, `app-build.log`,
`ui-all-complete.log`, `ui-files-complete.log`, `ui-complete.log`, and
`crossgates.log`. Final unit bundle: `CRS-complete.xcresult`; focused passing UI
bundles: `UI-complete.xcresult` and `UI-files-complete.xcresult`. Inspected restored
and deleted-home screenshots are in `validation-output/phase2b2/screenshots/`.

Evidence is under ignored `validation-output/phase2b2/`; full UI helper bundles
remain under `validation-output/phase15/` unless a focused result path is supplied.

## Physical iPhone status and checklist

Automated persistence, simulator termination/relaunch and fault-injection tests
**do not substitute for physical-device lifecycle testing**. Phase 2B.2 has not
been tested on the physical iPhone in this work. Earlier user-reported physical
CoreLocation/CRS-picker testing is not a persistence validation claim.

1. Import a project, confirm its CRS, select a non-first alignment and wait for
   **Project saved**.
2. Force quit and reopen. Check the home row, source/units, CRS/provenance and
   selected alignment; opening must not start location.
3. Explicitly start Field Position; verify station/offset, accuracy and
   stale-last-known behavior. Stop location.
4. Restart the phone and repeat reopen/restoration/Field Position checks.
5. Rename, force quit/reopen and verify the new name and original source filename.
6. Optionally replace with reordered/new source alignments; verify retained CRS
   and identity restoration or the unavailable-selection warning. Try a malformed
   replacement and verify the old source remains usable.
7. Cancel deletion once, then delete the test project and verify it stays removed
   after reopening.

## Limits and next Phase 2C scope

Storage is local to this app installation. Deleting the app removes its data;
there is no export/import project bundle, explicit backup UI, cloud sync or
multi-window shared editing. OS-managed backup behavior is not a substitute for
an engineering delivery/backup workflow. A damaged metadata database requires
recovery rather than silently rebuilding user confirmations from source files.
SwiftData V1 is the first persistent schema; migrations to future versions are
not implemented. Hash mismatch requires explicit re-import. Name-only identities
cannot track a rename in replacement XML; duplicate names/IDs require explicit
selection. Source replacement reports the new collection and selection failures,
not a semantic engineering geometry diff. In-flight choices cannot be guaranteed
saved if killed before **Project saved**. Power-loss, low-storage and device
restart checks still need physical testing. Parser/numerical limits are unchanged.

Recommended Phase 2C: add a small read-only MapKit context view for the explicitly
opened saved project and selected alignment. Inverse-transform display samples
through the existing adapter, keep engineering calculations in project space,
show quality/age/last-known status honestly and preserve explicit location start.
Start with known-point/axis/unit checks on the physical iPhone before claiming
map or GPS accuracy. Keep PDFs, photos, registration, surfaces, offline tiles and
cloud features outside that phase. No Phase 2C implementation began here.

## Files changed

- New `RoadStationProjects/{SavedProject,ProjectFileStore,ProjectRepository}.swift`
  and `RoadStationProjectsTests/ProjectRepositoryTests.swift` in the Apple package.
- Apple Package.swift library/target/test wiring; Xcode project app/test linkage
  and canonical CROSSGATES test resource.
- New app `SavedProjectsModel.swift`, project-root workflow in ProjectView.swift;
  removed the old session-only ProjectModel from HarnessModels.swift.
- FieldPositionSession restoration entry point and ConfirmedProjectCRS value
  initializer; one restoration regression test. Calculation code is untouched.
- UI lifecycle test, isolated UI storage and Files-fixture staging helper.
- CI full UI run, README.md, RoadStationApp/README.md and this report.
