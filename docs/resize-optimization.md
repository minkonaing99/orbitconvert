# Resize + Optimize

Scope: manual image actions. Watched folders and clipboard optimization do not resize automatically.

## Usage

Choose one or more supported images, open Tools, and choose Resize + Optimize.

Choose 25%, 50%, 75%, longest edge 1080 px or 1920 px, or custom maximum width/height. Custom dimensions are bounds: the image fits within them with its aspect ratio preserved. Images are never enlarged. The sheet previews the resulting dimensions, accounting for image orientation.

Balanced and Maximum control encoding quality. The existing Remove metadata setting applies. Output goes to the existing output destination, or a selected folder for a batch.

Results keep their image format and use `filename-resized.ext`, with numeric suffixes for collisions. Originals and existing outputs remain untouched. A valid result is published only when smaller; otherwise the action reports no useful size reduction.

## Architecture

`FileAction.resize` routes through `FileActionService` and the existing sequential `SelectionActionService`. Work runs in the existing detached manual-action task. No new background queue is introduced.

`ResizeOptionsView` collects options; `ImageResizeService` validates dimensions, prepares oriented pixels and delegates encoding to the existing optimization facilities. `FileOutputService` publishes only validated candidates with exclusive collision handling. Normal Compress continues to require unchanged image dimensions.

Orientation-aware ImageIO thumbnails are generated from full image data rather than trusting embedded previews. See Apple's [transformed thumbnail documentation](https://developer.apple.com/documentation/imageio/kcgimagesourcecreatethumbnailwithtransform).

## Safety and limits

The initial formats are single-frame JPEG, PNG and HEIC, subject to installed encoder availability. Unsupported high-bit-depth and gain-map inputs are rejected rather than silently flattened. PNG transparency and the image color space are retained; orientation and dimension metadata are normalized after resizing. Explicit metadata removal is respected.

Security-scoped access spans reading and publication. Generated workspaces are private and cleaned on success, failure and cancellation. Cancellation is checked before publication; synchronous codec operations finish before their next cancellation check. Protected PNG credentials continue to require explicit metadata removal.

Source dimensions are bounded before decoding. This is not an arbitrary-size image processor, a crop tool or a stretch tool. Undo is not part of this manual milestone because source files are kept.

## Validation

Automated cases cover dimension presets, custom fit, orientation, transparency, metadata, encoder availability, unsupported inputs, collisions, source preservation, cleanup and selection dispatch. Record actual build/test and coverage results in [testing](testing.md) after the complete run.

Manual checks: compare Preview orientation/color/alpha, test the main-window options sheet, resize mixed selections, cancel a large image, and select a writable output folder in an installed signed app. macOS 14 and Intel runtime validation require those environments.
