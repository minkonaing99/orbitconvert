# Image conversion

Status: Phase 3 reading and thumbnail generation are implemented and tested. Output encoding for conversion remains planned.

## Capability and detection

URL resource content information is a hint; ImageIO source type and thumbnail decode validate actual image data. A misleading extension does not determine the detected type. Full-resolution decode may still fail during Phase 4 conversion. Reject directories and invalid URLs before opening a source.

Phase 3 accepts single-image PNG, JPEG, HEIC/HEIF, and TIFF sources that ImageIO can preview. It queries [CGImageDestination supported type identifiers](https://developer.apple.com/documentation/imageio/cgimagedestination) and restricts displayed outputs to the planned allowlist, excluding the input format. Displayed capabilities are not a claim that conversion is implemented. HEIC encoding must still be verified on each supported architecture/runtime.

BMP and GIF input are later compatibility additions. Initially reject animated/multi-image files with a clear explanation rather than silently dropping frames or pages, including multi-page TIFF and multi-image HEIF. WebP and AVIF remain deferred.

## Encoding pipeline

1. Acquire source and destination access and validate options.
2. Inspect image count, dimensions, content type, orientation, and relevant metadata.
3. Decode off MainActor and apply the selected preservation policy.
4. Encode a new temporary file through CGImageDestination and check finalization.
5. Validate the produced file can be reopened, then publish through the safe-output service.
6. Report actual output URL, size, and any explicit preservation limitations.

Thumbnails use [CGImageSourceCreateThumbnailAtIndex](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)) with a bounded pixel size and orientation transform. They are never reused as conversion pixels.

## Pixel and metadata policies

- Preserve visible orientation. If physically normalizing pixels, set orientation to upright and swap dimensions for quarter turns; never apply the transform twice.
- Preserve image dimensions except the orientation normalization above. No implicit resize.
- Preserve the source color space/profile when representable. Use an explicit color conversion when required; do not merely relabel pixels. Test wide-gamut and grayscale inputs.
- Preserve DPI and compatible descriptive metadata by default. Do not promise byte-identical metadata across formats; remove stale structural fields after pixel transformations.
- JPEG is lossy and has no alpha. Proposed initial policy: flatten transparency onto white and disclose this before conversion. Preserve alpha for output paths proven to support it.
- Metadata stripping removes descriptive EXIF/IPTC/XMP/GPS fields and embedded previews. Retain pixel interpretation information such as required color data. Explain the distinction between personal metadata and color profile preservation.
- JPEG quality defaults to 0.90. TIFF/PNG encoding does not imply byte-identical output or a smaller file. Unsupported bit depth/HDR preservation must be reported, not silently claimed.

A future stripping tool must disclose when re-encoding changes quality. Compression reports actual original and result sizes; percentage saved is `(original - result) / original * 100` for a positive original size. If output grows, report the increase rather than negative savings presented as success.

## Dependencies

Use Apple ImageIO/Core Graphics first; Core Image only where transforms need it. No package or executable is needed for the initial scope. Research checked [Swift Package Index's ImageIO listings](https://swiftpackageindex.com/keywords/imageio) and [SDWebImage's ImageIO coder source](https://github.com/SDWebImage/SDWebImage/blob/master/SDWebImage/Core/SDImageIOAnimatedCoder.m); neither is adopted or copied.

Future PDF conversion uses PDFKit with explicit image ordering and page-size policy. Vision removal, WebP, and AVIF need separate capability and dependency decisions.

Related: [testing](testing.md), [architecture](architecture.md), [safe output](sandbox-and-output.md).
