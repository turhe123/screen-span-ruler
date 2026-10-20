# ScreenSpanRuler — specification

**Tagline:** Measure distances and gaps between any elements on screen in pixels using automatic edge detection.

**Category:** Screen & OCR

**Inspired by (paid):** Pixelsnap ($29 one-time)

**Frameworks:** SwiftUI, AppKit, CoreGraphics, ScreenCaptureKit, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: Pixelsnap by Ben Dahan sells for about 29 dollars one-time and is a screen ruler that snaps to the edges of whatever is on screen so designers can measure gaps and sizes in a single click. It is repeatedly recommended in designer and developer threads as the nicest way to measure UI. Our free clean-room version provides edge snapping measurement plus a few essentials.

Feature set: A global hotkey freezes the screen into a captured image and shows a crosshair. Moving the pointer draws horizontal and vertical measurement lines that extend from the pointer until they hit a strong color change, with the pixel distance labeled on each. Holding Shift locks to one axis. Click and drag draws a rectangle that shrinks to fit the content edges inside it and shows width and height. Arrow keys nudge by one pixel. A key toggles between points and true pixels on retina displays. Pressing C copies the current measurement as text. Escape exits.

UI spec: There is no main window. A MenuBarExtra with a ruler symbol offers Start Measuring, a unit toggle between points and pixels, a tolerance slider for edge sensitivity from zero to thirty, and Settings. The measuring overlay is a borderless full screen window per display showing the frozen screenshot with the crosshair lines in a bright accent color, and small pill labels with the numbers. A small help strip at the bottom of the screen lists the keys. Settings contain the hotkey recorder, default unit, tolerance, and launch at login. Empty and error states: if screen recording permission is missing, the Start item is replaced by a Grant Access item.

Technical approach: Check CGPreflightScreenCaptureAccess and request with CGRequestScreenCaptureAccess. Capture each display once with SCScreenshotManager into a CGImage and keep its raw RGBA bytes in memory. Edge detection scans outward from the pointer pixel along each of four directions comparing each pixel to the starting color by a max channel difference against the tolerance, and stops at the first pixel exceeding it. To avoid noisy results on gradients, compare to the previous pixel instead of the origin when the tolerance slider is high. Drawing uses SwiftUI Canvas inside an NSHostingView, with mouse moved tracking via NSTrackingArea. The hotkey uses Carbon RegisterEventHotKey. Preferences live in AppStorage and launch at login uses SMAppService.

Edge cases and error handling: Scale factors differ between displays, so convert between points and pixels per screen using backingScaleFactor and label units clearly. Dragging across displays is not supported, so clamp to the active display. Large 6K screens produce large buffers, so release the image when the overlay closes. If the capture fails, show a notification and exit gracefully. Menu bar and Dock regions are included because the capture covers the whole display. Keep the code between 350 and 600 lines.
