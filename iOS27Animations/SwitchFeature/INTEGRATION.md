# Integrated Theseus liquid switch source

This directory is compiled into the existing `iOS2627Anims.dylib` and shipped inside the existing iOS 27 Animations package. It does not produce, install, or filter a `TheseusSwitch.dylib`. The existing Theseus Swift/Metal implementation is retained here with its upstream license and source manifest.

In 1.5.7+ningzh1, Settings and SpringBoard publish the existing `LiquidSwitchEnabled` setting to `/var/mobile/Library/Accessibility/iOS27Animations-switch.plist`. The publishers migrate the saved value using the installation path of the main/prefs image. Settings publishes after saving, on page entry, and explicitly OFF on reset. The original preference key and default OFF are retained.

Every UIKit host reads the same validated snapshot instead of querying a foreign CFPreferences domain. The package depends on `com.opa334.libsandy` and installs one profile granting only read access to that exact configuration file. The RootHide profile uses `/rootfs/` to address the real mobile shared path. Invalid or unreadable updates retain the last valid ON/OFF state; only a validated OFF removes overlays. Foreground and bounded startup recovery re-read configuration. Metadata-only per-host diagnostics are written to `Library/Caches/iOS27Animations-switch.log`.

The original Clock reuse hooks, switch geometry, animations, renderer and vendored Theseus sources are preserved. Animation Logos hooks remain SpringBoard-only. Foundation regression tests validate the production snapshot helpers and apply function, but do not establish device injection or visible rendering.

The feature's Metal shader is compiled by `tools/prepare-switch-resources.py` into `Library/Application Support/iOS27Animations/TheseusSwitchResources.bundle`; the resource resolver anchors to the single `iOS2627Anims.dylib`.

The original Theseus LICENSE, NOTICE, upstream revision, and local patch manifest are preserved under `Vendor/`.

## Source provenance

- User-provided source: `TheseusSwitch-0.1.13-geometry-fix-source.zip`
- Archive SHA256: `a7117fd0d0053947ee65ae2c089865608614120439b3bf52897479068dbe4c30`
- Theseus original credit and full license: Ning&Vadim Drobinin, see LICENSE-Theseus and NOTICE-Theseus.
- Source-only integration; no independent tweak target, filter, package or installer script is imported.
