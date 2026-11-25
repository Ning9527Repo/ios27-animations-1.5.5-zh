# Package identity correction (0.1)

- Sileo display name (`Name`): **iOS 27 动画**, without a `Ning ·` prefix.
- Debian package identifier (`Package`): **com.ning.ios2627anims**.
- Deb filename: **com.ning.ios2627anims_0.1_iphoneos-arm64e.deb**.
- `Author` and `Maintainer`: **Ning**.
- Settings entry: retain the user-selected iOS 27 artwork (29/58/87 px).
- Sileo package artwork: no `Icon` field or package-artwork files.

The new identifier declares both `Conflicts` and `Replaces` against
`com.bazik1337.ios2627anims`, because both packages install the same tweak and
Settings entry. They must not be installed side by side. Keep the other
existing conflicts and replacements.

This change deliberately retains the old preferences domain and Darwin
notification namespace. Those are storage/runtime keys, not the Debian
package identity. Replacing them would lose access to saved settings or
require an unrelated migration. Rendering, QQ handling, Settings resources,
resource bundle identifiers and the code-signing configuration are unchanged.

Build validation must check the actual `Package`, display name and deb filename,
not merely rename a downloaded artifact. No software-repository publication or
automatic on-device installation is part of this identity correction.
