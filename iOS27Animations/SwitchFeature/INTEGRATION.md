# Integrated Theseus liquid switch source

This directory is compiled into the existing `iOS2627Anims.dylib` and shipped inside the existing iOS 27 Animations package. It does not produce, install, or filter a `TheseusSwitch.dylib`. The existing Theseus Swift/Metal implementation is retained here with its upstream license and source manifest.

The UIKit switch feature is controlled by `LiquidSwitchEnabled` in the existing `com.bazik1337.ios2627anims` preference domain. The switch overlay defaults off. UIKit hook wrappers remain inert when disabled; the shared Darwin preference notification enables or removes overlays in already-running apps. Animation Logos hooks remain SpringBoard-only.

The feature's Metal shader is compiled by `tools/prepare-switch-resources.py` into `Library/Application Support/iOS27Animations/TheseusSwitchResources.bundle`; the resource resolver anchors to the single `iOS2627Anims.dylib`.

The original Theseus LICENSE, NOTICE, upstream revision, and local patch manifest are preserved under `Vendor/`.

## Source provenance

- User-provided source: `TheseusSwitch-0.1.13-geometry-fix-source.zip`
- Archive SHA256: `a7117fd0d0053947ee65ae2c089865608614120439b3bf52897479068dbe4c30`
- Theseus original credit and full license: Ning&Vadim Drobinin, see LICENSE-Theseus and NOTICE-Theseus.
- Source-only integration; no independent tweak target, filter, package or installer script is imported.
