# Privacy and encryption audit — RoadStation 1.0

Scope: app source and pinned NGA projections-ios 3.0.0, coordinate-reference-systems-ios 2.0.0 and PROJ 9.4.2. Re-audit when dependencies or data flow change.

## Data flow and label

Files picker grants access to chosen documents; RoadStation copies bytes to app-owned Application Support storage. SwiftData persists project metadata, source fingerprint, selected CRS/alignment and import diagnostics. Projects are not excluded from OS backup. Delete removes app-owned source/metadata, not original files or historical backups. GPS fixes and query history are transient and location stops on leaving Field Position or inactive lifecycle. MapKit may request Apple map data. The app has no developer server, tracking, advertising, analytics, accounts or uploads.

App Store privacy label proposal: **Data Not Collected**, because RoadStation's developer does not receive app data off device. Apple's MapKit/system service processing is distinguished from developer collection. Optional support email and website processing are explained separately in the public policy. Confirm this against the final binary and App Store questionnaire before submission; do not label precise location as developer collection solely because it is processed locally.

## Required-reason APIs

PROJ FileManager::exists (src/filemanager.cpp, observed stat() call) checks accessible files. The linked Release executable has an undefined _stat reference. Calls operate on packaged projection resources and app-accessible files; no filesystem fingerprinting or timestamp transmission is implemented. App uses security-scoped Files access and app-owned project files. Manifest declares FileTimestamp reasons **C617.1** (app-container files) and **3B52.1** (files/directories specifically granted by the user). These reasons permit local metadata access, not sending it off device. No UserDefaults, disk-space, boot-time or active-keyboard required-reason usage was identified in app source. Pinned dependencies remain unchanged.

The manifest is shipped in the application resources; an automated check verifies exact entries. **Organizer's generated archive privacy report and final required-reason eligibility review remain required**, including transitive code not exercised by tests. A packaged manifest alone is not evidence that Apple has accepted the archive. Compare the report to the source/binary audit and resolve mismatches before upload.

## Encryption

CryptoKit is used for SHA-256 source fingerprints, not encrypting data. PROJ network access is disabled; there is no app-supplied TLS/encryption implementation. Apple MapKit HTTPS and system device/storage protection are operating-system services. No custom cryptography was found in the app or pinned projection code. On this audited scope, Info.plist declares ITSAppUsesNonExemptEncryption=false (only OS-provided/exempt behavior). Revisit if adding network clients, cloud sync, encryption libraries or features. Complete Apple's actual export-compliance questions on the submitted build.

Primary references:
- https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype
- https://developer.apple.com/app-store/app-privacy-details/
- https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/

## Icon provenance

AppIcon.png is an opaque 1024×1024 navy/white/teal mark generated with OpenAI image generation for this release: one roadway centerline with five station ticks, no text, gradient, border or baked-in corner mask. Xcode applies platform treatment. Check the icon in the signed archive and on a device before submission.
