# Pixel Rotator

macOS app that turns flat pixel art into a spinning sprite sheet. Drop orthographic views (or a few drawn angles), preview the turntable, then export a PNG sheet plus a JSON frame map, or a looping GIF.

The window opens on a built-in taxi. Replace those views with your own drawings.

## Requirements

- macOS 14 or later
- Swift 6 (Xcode 16 or a Swift 6 toolchain)
- No extra packages. The project is a Swift Package Manager app and links only Apple frameworks (`AppKit`, `CoreGraphics`, `ImageIO`).

## Run

From the repository root:

```sh
swift run PixelRotator
```

The first build compiles `PixelRotatorCore` and the app. Quit with ⌘Q, or close the window.

A release build:

```sh
swift build -c release
.build/release/PixelRotator
```

### Checks

`PixelRotatorCheck` is a second executable. It is not an app. It checks PNG round-trip, orthographic cameras, voxel carving, sheet packing, and the demo taxi, then writes sample images under `/tmp/pixel-rotator/` (`sheet.png`, `spin.gif`, `view-front.png`, and a few frames).

It is an internal target, so build it by name and run the binary:

```sh
swift build --target PixelRotatorCheck
.build/debug/PixelRotatorCheck
```

Success prints `OK`. A mismatch prints `FAIL` and exits with status 1.

## Using the app

The window has three panes: source drawings on the left, the preview in the middle, and export settings on the right.

**Flat views** is the default. Six slots: front, back, left, right, top, bottom. Drop PNG, JPEG, GIF, TIFF, BMP, or WebP files onto a slot, or onto the source list. File names are matched to a face when they contain `front`, `back` / `rear`, `left`, `right` / `side`, `top` / `above`, or `bottom` / `under`. Unmatched files fill empty slots. Switch to **Drawn angles** when you already have sprites facing specific directions instead of orthographic plans.

| Action | Shortcut |
| --- | --- |
| Load the demo taxi | ⌘D |
| Export sprite sheet | ⌘E |
| Export GIF | ⌘G |
| Play / pause the turntable | Space |
| Quit | ⌘Q |

Toolbar buttons cover the same demo, clear, GIF, and sheet actions.

### How a drawing becomes a solid

Transparent pixels are empty space, and a clear pixel is a hole through the whole object. Paint windows, lights, and other interior detail as opaque pixels. Images with no alpha can use **Key out a solid background**, which removes the corner color within **Key tolerance**.

Drawing orientation, with image Y growing downward:

| Face | The drawing should show |
| --- | --- |
| Front | The side that faces the camera at frame 0 |
| Back | The rear, as if you are looking at it |
| Left | Nose pointing right |
| Right | Nose pointing left |
| Top | From above, nose toward the top of the image |
| Bottom | The underside, nose toward the top of the image |

**Mirror the missing side** copies a left view onto the right (or the reverse) when only one side is supplied. **Thickness** fills any axis that has no drawing, so a lone front view becomes a slab that many voxels deep. **Detail cap** is the longest voxel axis. Views of different pixel sizes are resampled onto that one grid.

### Drawn angles

Each drawing has a facing in degrees. `0` is the front and `90` is the right side. **Mirror to the other side** flips a drawing across the spin (a `90°` drawing also fills `270°`). Frames between drawings are filled by **Hold nearest**, **Pixel dither**, or **Dissolve**. This path does not build a voxel model and ignores camera pitch.

### Preview and export settings

- **Steps** — frames in one full turn (4–128).
- **Camera** — pitch in degrees. `0` is side-on, `90` is straight down. Flat views only.
- **Shade the form** — a fixed light on the voxel faces.
- **Outline** — a one-pixel edge around each frame.
- **Pixel scale** — integer enlargement of each cell (1–8). Nearest-neighbor, so pixels stay square.
- **Columns** and **Gap** — how the sheet is packed.

The middle pane switches between the spinning **Turntable** and the packed **Sprite sheet**. Zoom only affects the preview.

**Export Sprite Sheet** writes a PNG and a sibling JSON file (`rotation-sprite-sheet.png` and `rotation-sprite-sheet.json` by default). The JSON lists frame rectangles, angle per frame, cell size, columns, rows, gap, pixel scale, camera pitch, and the pivot used to plant the sprite. **Export GIF** writes a looping GIF of the same frames. Duration is about 2.2 seconds per full turn.

## Architecture

```
Sources/
  PixelRotatorCore/   image, voxels, turntable, sheet packing
  PixelRotator/       AppKit window
  PixelRotatorCheck/  headless checks
```

`PixelRotator` is the only Swift package product. The app is a bare executable with no `Info.plist`: `PixelRotatorMain` installs an `NSApplication` delegate and calls `app.run()`. `MainWindowController` builds the window in code. `StudioModel` holds slots, settings, and the latest `SpinResult`, and rebuilds on a background queue after each edit.

Both modes go through `SpriteFactory`, which scales frames and packs them with `SpriteSheet`.

**Flat views**

1. `VoxelBuilder` starts from a solid grid. Each supplied view cuts away cells whose pixel is transparent. `ViewMap` is the shared mapping from voxel `(x, y, z)` to a pixel on each face.
2. Object axes: `+X` is the right side of the front drawing, `+Y` is up, `+Z` is the nose.
3. Surviving surface voxels keep the color of the nearest supplied view (`VoxelModel` stores only exposed cells).
4. `Turntable` yaws that model around up, pitches the camera, and rasterizes each step into a `PixelImage`. The viewport is stabilized so the sprite does not wander between frames.

**Drawn angles**

`DrawnAngles` lays the keyed drawings on one canvas and samples them at each step. No carving and no projection.

`ImageCoding` decodes imports through ImageIO (capped at 4096 px on a side) and writes PNG and GIF. `PixelImage` is a straight RGBA buffer. `DemoTaxi` sculpts the sample model in a `DenseGrid`; the app shows orthographic renders of that model, not the sculpt itself.

`PixelRotatorCore` does not import AppKit. The check target depends only on that module, which is why the carving and packing behavior can run without opening a window.
