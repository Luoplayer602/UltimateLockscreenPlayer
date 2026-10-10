# Artwork probe for iOS 15

Temporary rootless SpringBoard diagnostic package. ULP 65 stays installed unchanged.

## Scope

- Every 4 seconds for approximately 12 minutes after a respring: inspect UIImageViews in ULP/native media/Control Center hierarchies; record CGImage pixel dimensions, UIImage size/scale, view path and frame.
- Read the artwork bytes already returned by `MRMediaRemoteGetNowPlayingInfo` using ImageIO metadata; no full decode or image export.
- Record actual runtime class, method encodings and selected declared object ivar classes for artwork/provider/controllers. No guessed private requests/getters, view creation or mutation.
- All UI reads on main queue. Depth/view limits, deduplicated image state/class dumps, log cap 4 MiB. Stop timer after 180 samples. Log titles/artists to distinguish tracks; no audio/image files or network upload.
- Provider discovery is evidence for a later experiment, not proof that a high resolution request works. Visible image dimensions alone do not prove its freshness or that high resolution is available without opening Control Center.

## Build

From this folder: `make package FINALPACKAGE=1 THEOS_PACKAGE_BASE_VERSION=0.1.0-1`.

Package SHA-256: `aa5b4de41efada3002d6202e89da0cd9488edf4d503722fb481f94fe771abcf5`.

## Install and collect

```sh
ssh -tt -i ~/.ssh/ulp_iphone mobile@100.65.210.88 'sudo dpkg -i /var/mobile/com.luoplayer.ulpartworkprobe_0.1.0-1_iphoneos-arm64.deb && sudo killall SpringBoard'
```

Within 12 minutes, play a track with artwork. Hold each state 10–15 seconds: lockscreen with ULP, compact Control Center, expanded music panel (long press), return to lockscreen. Repeat with another track. Inspect `/var/mobile/Library/Logs/ULP-ArtworkProbe.log` through SSH. After `STOP`, another respring restarts sampling if still installed.

Read log:

```sh
ssh -i ~/.ssh/ulp_iphone mobile@100.65.210.88 'cat /var/mobile/Library/Logs/ULP-ArtworkProbe.log'
```

Remove when collection is complete:

```sh
ssh -tt -i ~/.ssh/ulp_iphone mobile@100.65.210.88 'sudo dpkg -r com.luoplayer.ulpartworkprobe && sudo killall SpringBoard'
```

Local build/package integrity checked. Device runtime collection is pending installation and UI reproduction. A separate older `com.luoplayer.ulpmediaviewprobe` was already present on the device; this package does not modify it.

## First device capture (2026-10-10)

Captured v1 log locally at `/tmp/ulp-artwork-probe-device.log` (3315 lines at read time). For `folern` by `nulut`, MediaRemote exposes title/artist but no artwork bytes. ULP/background and native lockscreen have 200×200 px images; compact Control Center has 100×100 px artwork. After expanding Control Center, artwork is 546×546 px in a 273×273 pt frame. 360×360 px images in small 16/24 pt frames are icons/badges or suggestions; do not use them as current track artwork.

Runtime provider: `MRUNowPlayingViewController._metadataController` is `MRUEndpointMetadataController`. It declares `_nowPlayingPlayerResponseArtworkCatalog` (`MPArtworkCatalog`) and `_nowPlayingPlayerResponse` (`MRNowPlayingPlayerResponse`). v1 confirms the larger image exists; it does not confirm a request path independent of expanding Control Center.

v2 (`0.1.0-2`) adds MPArtworkCatalog/response method discovery, size selectors, datasource/provider traversal (maximum three object edges), and deduplicates image logs despite zoom transforms. Same 12-minute limit. It remains read-only; no speculative private callbacks invoked.

SHA-256 v2: `7594fbc99d7c99f506b3865b68885b646ef3253854621b3b5573014ff2f49030`.
Install by replacing `0.1.0-1` with `0.1.0-2` in the command above. Repeat lockscreen → compact Control Center → expanded panel → lockscreen, including a track change.

User requested 1× centered foreground image in `Center dim image + blur background`. Working interpretation: at base zoom, no upscaling beyond one source pixel per physical screen pixel, so 546 px maps to 273 pt on this @2× display; downscale only if needed to fit viewport. Do not use UIImage.size directly because the captured large image reports scale=1 despite displaying at 273 pt. Blurred rear layer still covers viewport. Native implementation remains pending independent provider verification.

## v2 capture and v3 request experiment

v2 device log `/tmp/ulp-artwork-probe-device-2.log` confirms `MRUArtworkView._catalog` is `MPArtworkCatalog`, with `_dataSource` class `MPCMediaRemoteArtworkRemoteDataSource`, itself holding `MPCMediaRemoteController`. Actual runtime selectors include `setFittingSize:`, `requestImageWithCompletionHandler:`, `requestImageWithCompletion:` and `dataSource`. The expanded image remains 546×546 px. This identifies the provider but still does not prove a cold independent request succeeds.

v3 (`0.1.0-3`) is an active request experiment. It observes the block signature of a system `requestImageWithCompletionHandler:` call while passing the original call/completion unchanged. Only after verifying a void callback whose first argument is an object does it try an independent catalog using the lockscreen catalog's token/data source. It checks method signatures and size/scale encodings, sets only the new catalog to 750×750 at scale=1, requests an image and logs its dimensions. No returned image is applied to ULP or native views. At most 8 requests, one pending at a time, 8-second timeout; original catalog fitting size/context/destination stay unchanged. Sampling window remains 12 minutes.

Implementation references: [MPArtworkCatalog runtime header](https://github.com/nst/iOS-Runtime-Headers/blob/master/Frameworks/MediaPlayer.framework/MPArtworkCatalog.h) and [Clang's block ABI specification](https://clang.llvm.org/docs/Block-ABI-Apple.html). Actual device signatures take precedence over the older generated header. Callback extra arguments are ignored; only a UIImage result counts as an image success. If the callback's first object is a representation or error, log it and leave the result unhandled.

SHA-256 v3: `3c88bb81cac98939c2bc4f7656e290c516bc73af513704fb089f7793feb1320f`.

After installing v3, begin on lockscreen with playback and wait 15–20 seconds BEFORE opening Control Center. Then expand the music panel for 15 seconds, return, change track in the app, return to lockscreen and wait another 20 seconds without opening Control Center. This separates a new request from an image already fetched by the expanded panel. Look for `SYSTEM-COMPLETION`, `REQUEST-BEGIN`, `REQUEST-RESULT`/`REQUEST-TIMEOUT`; compare request metadata before/after, and pixel size against the ordinary 200 px image. Inability to verify callback or timeout is a failed experiment, not implementation success.

User also requested reduced scaling in Scaled dim image. Existing artwork fills an overscan container 30% taller than the physical viewport and then adds up to 8% zoom. Next native layout should compute aspect-preserving cover from the actual viewport, centered in viewport, and limit total extra scale to roughly 2% for this style. A square image on portrait display still requires side cropping to cover height; this requirement cannot preserve the entire subject if it reaches the sides. Center dim image + blur instead caps foreground size at one source pixel per display pixel and downsizes only to fit; rear blur fills the container. Geometry changes are planned, not deployed in this probe package.

## v3 result and v4 correction

Device v3 log `/tmp/ulp-artwork-probe-device-3.log` confirms version 0.1.0-3 with ULP 65, at least nine periodic sample markers and two track metadata values. No `SYSTEM-COMPLETION` and no `REQUEST-BEGIN` were recorded. The experiment never passed its callback-verification gate; it did not test the provider's ability to return a larger image. Do not classify this as a provider failure.

v4 (`0.1.0-4`) explicitly loads MediaPlayer and installs hooks on the main queue after runtime class availability, logging `HOOK-INSTALLED`; if class is absent it retries at the first sample ticks. It observes both request selectors and `setDestination:configurationBlock:`/`setDestination:progressiveConfigurationBlock:`. Original calls and completions are passed unchanged. Only a compatible actual void/object callback signature enables the independent request, which then uses the same verified selector family. For configuration callbacks it supports two object parameters with an optional BOOL third parameter; other signatures remain gated. The separate destination is retained alongside the separate catalog. A partial image does not release a progressive request until best/final, target size, or timeout. Probe still applies no returned image to any view.

SHA-256 v4: `c676412e81396db40d2bb9fb775d854f763778eb86da06d652375a226b1caaa0`.
Build and archive validation passed; runtime outcome pending. Repeat the v3 cold-lockscreen/change-track sequence using 0.1.0-4. If the verification gate remains closed, this version logs hook availability and observed route/signature so the reason is explicit rather than inferring an image request failure.

## v4 outcome — verified, native integration in 66

Runtime `HOOK-INSTALLED handler=1 completion=1 configuration=1 progressive=1`, then route 3 configuration callback `v24@?0@"MRUArtworkView"8@"UIImage"16`, verified. Independent lockscreen requests 1 and 2 returned 750×750 px. After switching from Nova (feat. Eye) / lapix to Break My Bones / Zekk, request 3 returned nil and timed out; request 4 returned 750×750. Request 5 later also returned 750×750. Original MediaRemote artwork remained zero bytes. This establishes a provider for the native implementation independent of copying the expanded Control Center UIImage.

ULP 66 integrates that separate-catalog request and bounded retry, current-track checks, prevention of image downgrades and the requested geometry. See `../../docs/NATIVE_ARTWORK_QUALITY_CONTRACT.md`. Remove this temporary probe when installing 66 to stop its sampling/hooks; it is not required by ULP 66. Native integration acceptance is separate from this successful probe.
