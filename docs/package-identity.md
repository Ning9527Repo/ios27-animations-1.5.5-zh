# Package identity correction (0.1)

- Sileo display name (`Name`): **iOS 27 动画**, without a `Ning ·` prefix.
- Debian package identifier (`Package`): **com.ning.ios2627anims**.
- Deb filename: **com.ning.ios2627anims_0.1_iphoneos-arm64e.deb**.
- `Author` and `Maintainer`: **Ning**.
- Settings entry: retain the user-selected iOS 27 artwork (29/58/87 px).
- Sileo package artwork: no `Icon` field or package-artwork files.

The old package identifier appears in `Conflicts` and `Replaces` only so dpkg
upgrades the existing package cleanly. It is not used for preferences,
notifications, bundles or runtime configuration.

The global preferences domain and Darwin notification namespace are owned by
this package: `com.ning.ios2627anims` and `com.ning.ios2627anims/changed`.
The previous author's identifier remains only in package upgrade metadata so
dpkg can replace the older package; it is not used for preference storage.
Rendering, QQ handling, Settings resources and code signing are otherwise
independent of package upgrade metadata.

Build validation must check the actual `Package`, display name and deb filename,
not merely rename a downloaded artifact. No software-repository publication or
automatic on-device installation is part of this identity correction.
