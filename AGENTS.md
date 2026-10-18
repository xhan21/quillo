# Quillo development handoff

Quillo (クイロ) is a native macOS teaching accessibility prototype, previously named ことば Local. Read README.md, docs/MAINTENANCE.md, docs/VALIDATION.md and CHANGELOG.md before making changes. Respond to the owner in concise, nontechnical Japanese.

## Product decisions to preserve

- A local Mac app that overlays captions on existing presentation apps. No hosted website, slide editor, or presenter notes.
- Speech captions update from partial recognition. Original only, translation only, and bilingual modes must switch without stopping capture or resetting the translation session. Keep regression coverage for this.
- Spoken captions use on-device Apple Speech and Apple Translation. Material summaries use OCR text from a user-selected screen region and local Ollama. Keep these separate.
- Japanese, English, Simplified Chinese, Traditional Chinese. Source/target settings are shared with material summaries.
- Material output is a concise translated summary only, in a separate floating panel with a prominent localized heading. No full-translation mode, manual page turning, or scrolling controls. Reading order is automatic.
- Subtitle and summary panels can be moved and resized. Fine controls belong in settings. Preserve existing preferences when updating.
- Do not send audio, screen images, recognized text, or logs to cloud services as an implementation shortcut. The model service is fixed to loopback and rejects cloud models.
- A glossary per teaching material was deferred; do not add it without a new request.

## Implementation and release

- Sources/ is native Swift/AppKit/SwiftUI. build.sh is the canonical build. test.sh runs the meaningful regression checks; Vision and live model checks need a suitable Mac.
- Keep CFBundleIdentifier and signing identifier jp.xuhan.KotobaLocal, preference keys, and internal executable name stable. These are intentional compatibility identifiers despite the new display name.
- Preserve third-party notices and the distinction between commentable as design inspiration and the adapted reading-order algorithm from class-material-translator.
- Verify the build and signature before installation. Quit the running app through the approved app-control tools before replacing it. Do not automatically start microphone capture or select a new screen-sharing target.
- Install the personal Mac copy at /Applications/Quillo.app when an update/install is requested. Explain when a restart requires capture to be selected again.
- Do not commit build outputs, models, personal teaching material, recordings, screen captures, transcripts, credentials, or local reference copies.
- Record the outcome and relevant validation in CHANGELOG.md and docs/VALIDATION.md so another chat can continue. Commit only the task's changes. Follow the user's current request for GitHub publishing and releases.
- Updates are on request. The owner chose not to schedule automatic maintenance. Do not silently replace models, download large model files, update macOS, or add an auto-update service.
