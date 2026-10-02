# App icon and local use

OrbitConvert uses an original generated icon: a folded document with blue and teal conversion arrows on a blue-gray tile. The transparent PNG assets are in `OrbitConvert/Assets.xcassets/AppIcon.appiconset`, covering macOS 16, 32, 128, 256 and 512-point slots at 1x and 2x. The 512-point 2x asset is the 1024-pixel master. Both app build configurations select `AppIcon`.

The artwork was created with the built-in image-generation tool, then edited to clean the transparent border. Prompt direction: original native macOS converter icon, broad blue/teal conversion arrows around a white folded document, restrained dimensionality, centered blue-gray tile, transparent exterior, no text or copied branding. Native `sips` produced the asset sizes. This is a raster icon; no layered Icon Composer source is supplied.

## Personal use

Build and run the existing OrbitConvert scheme in Xcode. No paid Developer ID certificate or notarization workflow was added. An ad-hoc signed local Release build can be produced with:

```sh
xcodebuild build -project OrbitConvert.xcodeproj -scheme OrbitConvert \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/OrbitConvert-local \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=
```

The app is at `/tmp/OrbitConvert-local/Build/Products/Release/OrbitConvert.app`. Quit the running app before opening a newly built copy. The Dock may retain an older icon until the app is relaunched. The separate monochrome menu bar symbol remains appropriate for menu bar rendering.

This local build is not a notarized public distribution. If public downloads are needed later, revisit Developer ID signing, notarization, a permanent bundle identifier and release privacy/distribution documentation.
