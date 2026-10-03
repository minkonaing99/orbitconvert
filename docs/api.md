# Internal API contracts

Status: Image and PDF detection, conversion, optimization, safe output, batch processing, and rectangular action panels are implemented. OrbitConvert has no network API, HTTP server, or OpenAPI schema.

## Core values

- FileItem: URL identity, URL, display name, extension, detected type identifier/name, byte size, optional creation date, pixel dimensions, bounded thumbnail data, and available conversion formats. URL permission is not retained after inspection.
- ConversionFormat: stable identifier, UTType, canonical extension, label, relevant options. Display JPG; write `.jpg`. Treat JPEG as the same format.
- ConversionResult: source and output URLs and original/result byte counts. No result URL until publication succeeds.
- ConversionOptions: JPEG quality in the closed range 0...1 (default 0.90) and metadata stripping flag. Reject nonfinite quality.
- FileAction: stable action kind, category, ID, title, and SF Symbol. The panel receives descriptors but never executes conversions itself.
- CompressionResult: source/output URLs and byte counts; savings and percentage are derived from the counts, with zero-byte input handled.

## Service boundaries

| Service | Input | Output and responsibility |
| --- | --- | --- |
| FileIntakeService | User-selected or dropped URLs | Local, regular, readable files and individual intake issues |
| FileTypeService | Validated local file URLs | ImageIO/PDFKit byte-based type, metadata, bounded thumbnail, installed output formats |
| ThumbnailService, if later needed | Image source and display bound | Downsampled, oriented preview |
| ImageConversionService | Validated job and temporary destination | Encoded image or typed error |
| PDFConversionService | Images or PDF and output options | Validated PDF creation, page rendering, extraction, and merge |
| ImageOptimizationService | JPEG/PNG and compression preset | Smaller validated candidate or no-reduction outcome |
| PDFOptimizationService | PDF and native PDFKit options | Structure-checked smaller candidate or no-reduction outcome |
| BatchOptimizationService | Ordered files and output folder | Sequential results, skipped files, and per-file failures |
| BatchConversionService | Files with a common JPEG/PNG target | Sequential conversion through ImageConversionService with per-file results |
| FileActionService | Action descriptor and settings | Dispatch to conversion or optimization outside the panel UI |
| FileOutputService | Authorized directory and proposed basename | No-overwrite publication with collision retry |
| SecurityScopedAccessService | User-granted URL/bookmark | Scoped lifetime, bookmark resolution and renewal |
| Conversion coordinator | Immutable jobs | Ordered progress, cancellation, per-file results |

The coordinator composes services. Views do not decode, encode, acquire persistent permissions, or choose collision names themselves.

## Errors

| Error | User-facing meaning |
| --- | --- |
| unsupportedInput | This file type is not supported |
| unsupportedOutput | This output format is unavailable on this Mac |
| cannotDecode | This image could not be opened; it may be damaged |
| cannotEncode | This image could not be converted to the selected format |
| cannotWriteFile | The result could not be saved; check space and destination |
| permissionDenied | OrbitConvert does not have permission; choose an authorized folder |
| invalidDestination | Choose an available folder for the output |

Cancellation is a separate expected terminal state, not a failure alert. Keep underlying errors for redacted diagnostics without exposing raw NSError text as the default UI.

## Future actions

`FileAction.resize` is a manual tool for single-frame JPEG/PNG/HEIC with an available encoder. `FileActionSettings.resizeOptions` defaults to 50%. `ResizeOptions.dimensions` computes aspect-fit output without enlargement. `ImageResizeService.resize` returns the existing `OptimizationOutcome`, preserving the original and publishing only a smaller validated separate output. See [resize contracts](resize-optimization.md).

Action descriptors drive UI; services own work. A dynamic code-loading plugin system is not needed. See [PDF and compression](pdf-compression.md) for native backend limits.

Related: [architecture](architecture.md), [output](sandbox-and-output.md).
