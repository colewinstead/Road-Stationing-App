---
target: Road Stationing iOS app field-use critique
total_score: 26
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 3
target_identity: "file:/Users/colewinstead/1Python/Road-Stationing-App/RoadStationApp/RoadStationApp/AlignmentWorkspace.swift"
target_fingerprint: "sha256:b855b237a4c4b403e1d0fb34a7ed7c8c8a8e0e1f85e751e21e0aaf2e337d9982"
target_path: /Users/colewinstead/1Python/Road-Stationing-App/RoadStationApp/RoadStationApp/AlignmentWorkspace.swift
timestamp: 2026-10-04T17-58-22Z
slug: p-roadstationapp-alignmentworkspace-swift-6aabeed1
---
Method: dual-agent (A: /root/design_review_resume · B: /root/evidence_review_resume)

Created local branch `codex/field-ui-critique` from `codex/Phase2b.2`. No application code changed.

RoadStation has strong engineering vocabulary and useful safeguards, but its screen structure still prioritizes inspection and project administration. The highest-value improvement is a field screen that answers “Where am I, relative to this alignment, and how trustworthy is this reading?” in one glance.

**Highest-value improvements, in order**

1. **[P1] Keep the field reading and location control together.** Start/Stop follows the result, coordinates, CRS, units and explanatory text in [FieldPositionView.swift](/Users/colewinstead/1Python/Road-Stationing-App/RoadStationApp/RoadStationApp/FieldPositionView.swift:130). This can require scrolling precisely when the user needs a quick thumb action. Keep station, offset, alignment, accuracy and freshness visible together; move Easting/Northing and setup details into disclosure. Put a large Start/Stop control in the bottom safe area, with its label reflecting the current state. Preserve explicit starting and the current foreground-only policy. Suggested command: `$impeccable adapt`.

2. **[P1] Show the live position against the alignment.** Field Position is a numeric screen; the separate engineering canvas plots manual query points, not GPS. Switching between them demands mental translation and stops location when leaving Field Position. Reuse the planar canvas for a compact field view with the projected phone position, nearest alignment point, uncertainty indicator and increasing-station arrow. Distinguish live position from a manually inspected point. Provide Follow, Recenter and Fit Alignment; panning should pause following without stopping GPS. A geographic basemap can be a later step if site context proves necessary. Evidence: [AlignmentWorkspace.swift](/Users/colewinstead/1Python/Road-Stationing-App/RoadStationApp/RoadStationApp/AlignmentWorkspace.swift:17), [EngineeringCanvas.swift](/Users/colewinstead/1Python/Road-Stationing-App/RoadStationApp/RoadStationApp/EngineeringCanvas.swift:39). Suggested command: `$impeccable shape`.

3. **[P1] Make the critical reading resilient to glare and larger text.** The live station uses a fixed 34-point font; the main status is limited to two lines. Caption/secondary text and orange warnings deserve outdoor scrutiny. Use scalable station typography, natural warning wrapping, strong text contrast, and icons plus words for stale, poor-accuracy and ambiguous states. Keep LT/RT tied visibly to increasing station direction. Aim for 44 × 44-point minimum targets, with larger primary field actions. These follow [Apple’s interface guidance](https://developer.apple.com/design/tips/) and [Dynamic Type guidance](https://developer.apple.com/videos/play/wwdc2024/10074/). No measured contrast failure or actual text clipping was established. Evidence: [FieldPositionView.swift](/Users/colewinstead/1Python/Road-Stationing-App/RoadStationApp/RoadStationApp/FieldPositionView.swift:80). Suggested command: `$impeccable typeset`.

4. **[P2] Make returning to field work the obvious route.** Project metadata precedes both “Continue [alignment]” and “Live Location / Field Position.” A returning inspector has to choose between two paths before doing the primary job. Lead with the saved alignment, CRS readiness and one prominent “Open Field Position” action. Label the secondary route “Inspect Alignment”; disclose source filename/date and other administration. Keep alignment switching accessible and explicit. Evidence: [ProjectView.swift](/Users/colewinstead/1Python/Road-Stationing-App/RoadStationApp/RoadStationApp/ProjectView.swift:117). Suggested command: `$impeccable distill`.

5. **[P2] Put recovery beside the warning and remove contradictory guidance.** A retained result can say “Last known position — update unavailable,” while the specific cause appears farther down in CRS controls. Show the reason and relevant action beside the reading: Open Settings for denied permission, guidance while waiting for a fresh fix, or Review CRS for a conversion problem. Keep stale/ambiguous labels attached to the numbers and preserve the existing calculation safeguards. Also replace “Selection lasts for this session”: confirmed CRS is now saved with the project. Evidence: [FieldPositionSession.swift](/Users/colewinstead/1Python/Road-Stationing-App/RoadStationApp/CRSAdapter/Sources/RoadStationFieldPosition/FieldPositionSession.swift:17), [FieldPositionView.swift](/Users/colewinstead/1Python/Road-Stationing-App/RoadStationApp/RoadStationApp/FieldPositionView.swift:43). Suggested command: `$impeccable clarify`.

**What already works**

- Large station/offset readings use familiar roadway notation; accuracy and fix age accompany them.
- CRS confirmation, unit handling, ambiguity warnings and last-known labeling protect engineering meaning.
- Saved project choices, safe source replacement and native navigation reduce repeat setup and data-loss friction.

**Design specificity and cognitive load**

The terminology is specific to RoadStation; the stacked metadata-and-tool layout feels like a developer harness. Product character should come from precise field information and spatial orientation. Four cognitive-load checks fail across the workflow: primary hierarchy, one decision at a time, remembering context between drawing and GPS, and progressive disclosure. The four workspace tabs are manageable; the extra field route and CRS alternatives create competing paths. Simultaneous visibility of every CRS action was not established.

**Persona checks and emotional journey**

- Casey, using one hand: location controls can fall below the viewport; interruptions require a clear, reachable restart.
- Sam, needing larger text: station sizing and constrained warning text need accessibility-size checks; the canvas has labels but lacks equivalent accessible spatial interaction.
- Jordan, opening a project for the first time: “Continue” and “Live Location / Field Position” compete; a simple alignment → CRS → Start sequence would clarify readiness.

Import and CRS selection are the effort-heavy entry; the large station reading is the payoff. Returning after an interruption should quickly restore orientation and offer an explicit restart.

**Heuristic score: 26/40 — Acceptable; significant field-use improvements needed.** Scores are review judgments, not usability-test measurements.

| Heuristic | Score / 4 | Main issue |
|---|---:|---|
| System status | 3 | Important warning space is constrained |
| Real-world match | 3 | Developer terminology leaks into supporting flows |
| Control and freedom | 3 | Stop/restart requires reaching a lower card |
| Consistency | 3 | CRS persistence copy contradicts behavior |
| Error prevention | 3 | Strong safeguards; readiness could be clearer |
| Recognition over recall | 2 | Drawing and live position require mental translation |
| Efficiency | 2 | Returning field access is indirect |
| Minimalist design | 2 | Metadata competes with the primary task |
| Error recovery | 3 | Specific field failure reasons are remote |
| Help | 2 | Cautions are stronger than next-step guidance |
| **Total** | **26/40** | **Acceptable** |

**Smaller improvements**

Label manual inputs with project units, place form errors beside submission, and move Raw/zero-based branch details into advanced inspection. Improve canvas marker shapes and direction cues rather than relying on color alone. Debug samples and injection controls are clearly labeled and excluded from Release; their clutter should not be counted as a production defect.

**Independent evidence**

Both assessments agree on field-control placement and text scaling. The technical pass adds error locality and manual-input unit labels. The detector returned zero findings, but meaningful SwiftUI coverage was not established; that is not an accessibility pass. No detector false positives were returned.

Existing native screenshots support the broad hierarchy, but capture freshness was not established. Current source takes precedence over older screenshots. Fresh Simulator UI access failed with `Invalid app`; no fresh build completed. Dark mode, accessibility text sizes, VoiceOver, outdoor readability, GPS field behavior and physical thumb reach remain unverified.

**Choices for a later design pass**

1. First focus: **readable field screen and thumb controls**, **live alignment view**, or **faster project-to-field access**?
2. Scope: **reuse the planar canvas**, or **plan geographic MapKit context as well**?
