# Preparing document helpers

The repository contains OrbitConvert source, helper licenses and notices. Pandoc and Ghostscript executables are local build inputs and are not committed. A fresh clone must prepare these inputs before building. The existing local installation already has them; no setup is needed there.

These instructions reproduce the Apple Silicon helper setup. Intel executables and macOS 14 runtime remain unverified. Downloads occur only during this explicit setup, never during app execution or Xcode builds.

## Verified downloads and local build

Run from the repository root. Xcode command-line tools, curl, unzip, tar, gzip and make are required.

```sh
repositoryRoot="$PWD"
toolWorkspace="$(mktemp -d "${TMPDIR:-/tmp}/OrbitConvert-setup.XXXXXX")"
cd "$toolWorkspace"

curl --fail --location --output pandoc.zip https://github.com/jgm/pandoc/releases/download/3.12/pandoc-3.12-arm64-macOS.zip
printf '%s  %s\n' f148ca09c9f36594db527a9fc988ad736290ce428f79594c50208cd1ec58b3c0 pandoc.zip | shasum -a 256 -c -
```

Stop if verification does not report `OK`. Then extract and prepare the local Pandoc build input:

```sh
unzip -q pandoc.zip
gzip -n -c pandoc-3.12-arm64/bin/pandoc > "$repositoryRoot/ThirdParty/pandoc/pandoc.gz"

curl --fail --location --output ghostscript.tar.gz https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs10080/ghostscript-10.08.0.tar.gz
printf '%s  %s\n' caf199e3f233f1290b27d0972d636f66c303355f2353309b7bfddf1edda06b3d ghostscript.tar.gz | shasum -a 256 -c -
```

Stop if Ghostscript verification does not report `OK`. Then build its executable from the verified upstream source:

```sh
tar -xzf ghostscript.tar.gz
cd ghostscript-10.08.0
env PATH=/usr/bin:/bin:/usr/sbin:/sbin MACOSX_DEPLOYMENT_TARGET=14.0 ./configure --without-tesseract --without-libidn --without-libpaper --without-x --disable-fontconfig --disable-cups --disable-dbus --prefix=/tmp/orbitconvert-gs
env PATH=/usr/bin:/bin:/usr/sbin:/sbin make -j4
gzip -n -c bin/gs > "$repositoryRoot/ThirdParty/ghostscript/gs.gz"
cd "$repositoryRoot"
```

If a command fails, stop rather than continuing with partial assets. Successful Xcode builds decompress and sign these helpers inside the app. Local gzip assets remain ignored by Git. The temporary setup directory can be removed once setup succeeds; keep upstream source if preparing a distribution.

Exact provenance, original binary hashes and backend limits are recorded in [implementation](markdown-pdf-implementation.md). A locally rebuilt executable can differ by compiler/build environment.

## Distribution

This setup is for personal local builds. It does not establish license compliance for distributing a built app. Before distributing GPL/AGPL helper binaries, review corresponding-source and notice obligations. Source-only repository publication does not publish these executable caches. See the [GNU license FAQ](https://www.gnu.org/licenses/gpl-faq.en.html) and [Ghostscript license information](https://ghostscript.com/faq/).
