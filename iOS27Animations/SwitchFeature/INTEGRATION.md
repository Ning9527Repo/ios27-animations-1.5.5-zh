# Integrated Theseus liquid switch source

This directory is compiled into the existing `iOS2627Anims.dylib` and shipped inside the existing iOS 27 Animations package. It does not produce, install, or filter a `TheseusSwitch.dylib`. The existing Theseus Swift/Metal implementation is retained here with its upstream license and source manifest.

In 1.5.7+ningzh1, Settings and SpringBoard publish the existing `LiquidSwitchEnabled` setting to `/var/mobile/Library/Accessibility/iOS27Animations-switch.plist`. The publishers migrate the saved value using the installation path of the main/prefs image. Settings publishes after saving, on page entry, and explicitly OFF on reset. The original preference key and default OFF are retained.

Every UIKit host reads the same validated snapshot instead of querying a foreign CFPreferences domain. The package depends on `com.opa334.libsandy` and installs one profile granting only read access to that exact configuration file. The RootHide profile uses `/rootfs/` to address the real mobile shared path. Invalid or unreadable updates retain the last valid ON/OFF state; only a validated OFF removes overlays. Foreground and bounded startup recovery re-read configuration. Metadata-only per-host diagnostics are written to `Library/Caches/iOS27Animations-switch.log`.

In 1.5.8+ningzh1, non-Clock replacements live inside the owning native UISwitch. Only its native drawing sublayers receive reversible empty masks; the host's alpha, position, hide/show and reuse lifecycle remain authoritative. A UISwitch-only hit-test adapter forwards touch to that switch's replacement. Pressed glass is confined to its owner and captures that track, avoiding page-level floating lenses. A press ticket includes source, parent, reusable cell, list and index path; stale commits/releases are cancelled after reuse or host rejection.

Clock keeps its existing sibling mounting, row reset and replay paths. Animation Logos hooks remain SpringBoard-only. Host-side tests exercise extracted production snapshot, binding, mask, geometry, finishPress and identity code on Foundation/CALayer/Swift stand-ins; these do not establish UIKit/QQ device behavior. Optical material parameters, original motion constants, shaders and renderer are unchanged.

The feature's Metal shader is compiled by `tools/prepare-switch-resources.py` into `Library/Application Support/iOS27Animations/TheseusSwitchResources.bundle`; the resource resolver anchors to the single `iOS2627Anims.dylib`.

The original Theseus LICENSE, NOTICE, upstream revision, and local patch manifest are preserved under `Vendor/`.

## Source provenance

- User-provided source: `TheseusSwitch-0.1.13-geometry-fix-source.zip`
- Archive SHA256: `a7117fd0d0053947ee65ae2c089865608614120439b3bf52897479068dbe4c30`
- Theseus original credit and full license: Ning&Vadim Drobinin, see LICENSE-Theseus and NOTICE-Theseus.
- Source-only integration; no independent tweak target, filter, package or installer script is imported.
