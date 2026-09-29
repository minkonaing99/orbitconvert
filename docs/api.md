# Internal API contracts

Status: FileItem, ConversionFormat, intake, type inspection, conversion, and safe output are implemented. OrbitConvert has no network API, HTTP server, or OpenAPI schema.

## Core values

- FileItem: URL identity, URL, display name, extension, detected type identifier/name, byte size, optional creation date, pixel dimensions, bounded thumbnail data, and available conversion formats. URL permission is not retained after inspection.
- ConversionFormat: stable identifier, UTType, canonical extension, label, relevant options. Display JPG; write `.jpg`. Treat JPEG as the same format.
- ConversionResult: source and output URLs and original/result byte counts. No result URL until publication succeeds.
- ConversionOptions: JPEG quality in the closed range 0...1 (default 0.90) and metadata stripping flag. Reject nonfinite quality.

## Service boundaries

| Service | Input | Output and responsibility |
| --- | --- | --- |
| FileIntakeService | User-selected or dropped URLs | Local, regular, readable files and individual intake issues |
| FileTypeService | Validated local file URLs | ImageIO byte-based type, metadata, bounded oriented thumbnail, installed output formats |
| ThumbnailService, if later needed | Image source and display bound | Downsampled, oriented preview |
| ImageConversionService | Validated job and temporary destination | Encoded image or typed error |
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

When tools arrive, introduce FileAction descriptors and FileActionHandler with identifier, displayName, iconName, canHandle, and async execute responsibilities. Descriptors drive UI; handlers own work. Register built-in handlers in app composition, not a dynamic code-loading plugin system. Add explicit batch input only when merge/collection actions require it.

Related: [architecture](architecture.md), [output](sandbox-and-output.md).
