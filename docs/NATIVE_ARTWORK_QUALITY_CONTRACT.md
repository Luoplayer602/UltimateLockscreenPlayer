# Artwork quality — ULP 0.1.0-66 / 67

The 66 sections below describe the original implementation. **67 supersedes its foreground sizing and zoom** as specified in the acceptance update at the end.

## Verified provider on the test device

iPhone 6s, iOS 15.8.5, Dopamine. ULP 65 functions accepted; artwork backgrounds pixelate because their source image is 200×200 px. Compact Control Center uses 100×100; expanded Control Center uses 546×546 in a 273 pt frame. Enlarging either small image cannot recover detail.

Probe v4 independently cloned the lockscreen `MRUArtworkView._catalog` token/data source. `MPArtworkCatalog` with `MPCMediaRemoteArtworkRemoteDataSource`, fitting size 750×750 and destination scale 1 returned **750×750 px**. Actual configuration callback ABI: `v24@?0@"MRUArtworkView"8@"UIImage"16` (void, destination object, UIImage). The destination was an independent retained NSObject. No original catalog size, destination or callback was modified.

Device evidence from `/var/mobile/Library/Logs/ULP-ArtworkProbe.log`:

| Time in log | Result |
| --- | --- |
| 1791629744.425 → 1791629745.866 | Independent lockscreen request 1 → UIImage 750×750 |
| 1791629748.337 → 1791629748.539 | Request 2, Nova (feat. Eye), lapix → 750×750 |
| 1791629836.329 → 1791629844.338 | Request 3, Break My Bones, Zekk → nil, timeout |
| 1791629848.304 → 1791629848.365 | Retry request 4 → 750×750 |

The provider can return nil transiently. 750 px is a requested size, not a guarantee for every track/app. This verifies the provider request; native 66 UI integration still needs device acceptance.

## Native integration

- `Playback/ULPArtworkProvider` only scans the **current player's native host**, excluding the ULP view. Only `MRUArtworkView` with at least 40 pt extent is eligible; badges/suggestions elsewhere in Control Center are not image sources.
- Clone token/data source into an independent catalog and retain its destination. Guard method signatures and size/scale argument encodings before requesting. The callback implementation uses the ABI verified on this test device.
- All view/runtime reads and request state run on the main queue. Callback work is dispatched there.
- One pending request per provider, eight-second deadline, at most four attempts per track/host generation, with 2/4/8-second retry spacing after completion/timeout. A partial result may upgrade the current picture while the request waits for the target size or deadline.
- Track identifiers include source PID, title and artist. On track/session changes, invalidate pending tickets and clear current artwork. Reject the preceding catalog token until a fresh token appears. On callback, recheck generation, track, host/window, native view membership and current token. Old-host image handlers cannot publish through the active player.
- Both player and global background cache accept only higher pixel area within the same track. Thus 200 px updates cannot overwrite a 750 px image. Nil results keep the current track's image; they never bring back the preceding track's image.
- Existing standard snapshot/native artwork remains the fallback. Missing methods/provider do not prevent the player from displaying its ordinary image.
- The high-resolution image also feeds the existing Preview artwork cache. Preview may refresh on its existing cache polling interval.
- Native diagnostics use `Artwork HQ begin/result/timeout/discarded/exception` in `/var/mobile/Library/Logs/ULP.log`. Probe is removable and not a runtime dependency.

PID/title/artist is the existing track identity contract: different recordings with identical title/artist within one process are not distinguishable by this key alone. Retain this as a limitation for future metadata identity work.

## Background geometry

Rear blur retains the existing overscan/swipe container. Foreground geometry uses `contentViewport`, the actual visible screen, rather than the 30% taller overscan bounds.

- **Center dim image + blur:** base size is oriented source pixel dimensions divided by the physical display scale. No enlargement. Reduce proportionally only to fit viewport. Example: 546 px → 273 pt on @2×; 750 px → 375 pt. A landscape thumbnail stays centered over full rear blur. Foreground stays at this size during audio zoom; rear blur keeps its existing audio motion.
- **Scaled dim image:** smallest aspect-preserving cover of the viewport, centered there. Square artwork on a 375×667 pt screen is 667×667 pt, before at most 2% extra audio zoom. Its upper/lower edges meet or slightly exceed screen height; side cropping is unavoidable when covering portrait with square/landscape artwork.
- **Blur background:** existing full blurred layer and audio motion.
- Embedded and full-screen Preview share the same layout code, using their own viewport and display scale.

DSP/server, player placement, controls, recovery, clock hiding and volume HUD are unchanged by this work. Lyrics remains paused.

## Verification and acceptance

`make -C Tests test`: request generation/retry limits, old callback rejection, image quality ranking, source-pixel/display-scale geometry and existing regression suites. Arm64/rootless package build and full archive decompression must succeed before transfer; remote package SHA-256 must match.

Device acceptance:

1. After respring, play a track and wait on lockscreen **without opening Control Center**. Look for `Artwork HQ result ... pixels=750x750`; compare sharpness with 65.
2. Try Center dim image + blur and Scaled dim image, Apply each. Verify centered 1× foreground, full rear blur, reduced cover crop/zoom and swipe coverage.
3. Change tracks quickly, pause, lock/wake and kill/reopen YouTube Music several times. Picture must belong to the current song, retain quality and recover with the player.
4. Check Settings Preview and all background types. Track changes must not leave the old picture, blank screen or misplaced player. Watch memory/performance during longer use.

Install 66, then remove the temporary artwork probe, respring once:

```sh
ssh -tt -i ~/.ssh/ulp_iphone mobile@100.65.210.88 'sudo dpkg -i /var/mobile/com.luoplayer.ultimatelockscreenplayer_0.1.0-66_iphoneos-arm64.deb && sudo dpkg -r com.luoplayer.ulpartworkprobe && sudo killall SpringBoard'
```

No server package update. If necessary, reinstall the existing ULP 65 package and respring.

Build/archive validation and Tests passed. Package: `com.luoplayer.ultimatelockscreenplayer_0.1.0-66_iphoneos-arm64.deb`, 21225594 bytes, SHA-256 `028958383b3b1ca11a5ff59b55510cbbfa7fde1b015f4f71641a0f1bab624b9b`. Copied to `/var/mobile` with matching remote SHA-256 before renaming `.part` to final name. Manual install and native UI acceptance pending.

## 67 acceptance update: restore background motion

User accepted the higher-resolution image from 66, but reported that Center dim image had no foreground zoom and Scaled image had too little. Preserve the accepted provider/cache behavior. Center foreground now uses 83% of viewport width at rest (independent of source resolution), retaining aspect ratio and enough vertical room for 8% zoom. At maximum zoom its width is 89.64% of the viewport. Height is limited to viewport height / 1.08 for portrait artwork or compact Preview. Rear blur still fills the container.

Both foreground styles use the original `1 + clamp(level, 0, 1) * .08`, smoothing coefficient .35, matching rear blur. Scaled image keeps minimal cover of the actual viewport, rather than returning to the oversized 30% overscan crop. Shared native Preview uses these same changes. DSP and artwork provider are unchanged.

67 also fixes the player progress restart reported when pressing Previous once in YouTube Music; see `NATIVE_PLAYER_RECOVERY_CONTRACT.md`. Device acceptance: check centered artwork width and zoom, Scaled image zoom/crop, Previous once → progress 0:00 in same song, Previous again near start → previous song, pause/resume and seek. Native UI acceptance remains pending.

67 Tests, arm64/rootless build and full archive decompression passed. Package `com.luoplayer.ultimatelockscreenplayer_0.1.0-67_iphoneos-arm64.deb`: 21224746 bytes, SHA-256 `9b2889353e12139e8bf507be30b81fbe33e2bf25b5f3c7a8d6b4da2d79321260`. Copied to `/var/mobile` and verified identical remote SHA-256 before renaming `.part`. Manual install remains necessary; no probe/server update required.

## 68: centered artwork corners

User accepted 67, including zoom and progress, and requested rounded corners on Center dim image + blur. The foreground UIImageView uses continuous corners with radius 6.5% of its shorter base dimension, capped at 24 pt (about 20 pt for the tested 375 pt screen). Its existing clipping keeps the image inside those corners, and the existing transform scales image/corners together. Scaled and blur-only styles keep radius zero. Native lockscreen, fixed/moving backgrounds and Settings Preview use the same class. Source quality, 83% framing, 8% zoom and progress logic remain as accepted in 67.

See `PRE_RELEASE_NOTES.md` for a proposed beta announcement; release/tag publication is not part of this change. Corner appearance still needs device acceptance.

68 build and existing Tests passed; archive fully decompressed. Package size 21218750 bytes, SHA-256 `809f166f7af77def16607e2934d49398d92848658719b7be21f5730265538ae3`. Transferred to `/var/mobile` with matching remote checksum before renaming `.part`. README build commands also verified for server `2.1.1+ulp2`; no server reinstall needed on the accepted test setup.
