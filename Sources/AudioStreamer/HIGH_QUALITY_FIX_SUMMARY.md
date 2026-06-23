# High Quality Infinite Skip Bug - Fix Summary

## Problem Description

When users selected "High" audio quality, the app would enter an infinite play/skip loop, rapidly cycling through songs without playing any audio. This bug had multiple contributing factors:

### Root Causes

1. **HE-AAC Codec Handling (AudioStreamer.m)**
   - Free Pandora accounts receive HE-AAC (AAC+) encoded audio for the "highQuality" tier
   - AudioStreamer was only reading the base AAC format without SBR extension
   - The audio queue was configured for half-sample-rate base AAC
   - This produced zero decodable audio packets
   - The stream immediately reported "done" with no audio

2. **Quality Tier Selection (Pandora.m)**
   - The high quality tier was selected without checking if the codec was decodable
   - Undecodable codecs would be queued anyway
   - No fallback to lower quality tiers when encoding wasn't supported

3. **Missing Tier Fallback (Pandora.m, Station.m)**
   - Some quality tiers could be missing (e.g., Pandora One accounts don't get "lowQuality")
   - Missing tiers could result in nil URLs being queued
   - No cross-tier fallback logic

4. **Infinite Skip Loop (ASPlaylist.m)**
   - When a stream "finished" with zero audio packets, playlist would immediately call `next`
   - This repeated infinitely fast, burning through the entire station
   - No detection mechanism to stop the runaway skip

## Applied Fixes

### 1. AudioStreamer.m - HE-AAC FormatList Handling

Added `kAudioFileStreamProperty_FormatList` case to properly detect and configure HE-AAC streams:

```objc
case kAudioFileStreamProperty_FormatList: {
  // Read the format list
  // Use AudioFormatGetProperty with kAudioFormatProperty_FirstPlayableFormatFromList
  // Select the SBR-extended ASBD (kAudioFormatMPEG4AAC_HE)
  // Update asbd BEFORE createQueue runs
}
```

This ensures the audio queue is configured for the full-rate SBR format, not just the base layer.

### 2. Pandora.m - Encoding Decodability Check

Added `+encodingIsDecodable:` method to validate codec support:

```objc
+ (BOOL) encodingIsDecodable:(NSString *)encoding {
  // Returns YES for: mp3, aac, aacplus, he-aac, etc.
  // Returns NO for: opus, flac, and unknown future codecs
  // Treats nil/empty as decodable (assume MP3)
}
```

### 3. Pandora.m - Quality Tier Selection Fix

Extracted and fixed `+populateAudioUrlsForSong:fromItem:`:

- Only sets `highUrl` when encoding is decodable
- Implements comprehensive fallback logic:
  - `lowUrl` falls back to `medUrl` or `highUrl`
  - `medUrl` falls back to `lowUrl` or `highUrl`
  - `highUrl` falls back to `medUrl` or `lowUrl`
- Guarantees all three URL properties are non-nil if ANY audio URL exists

### 4. Station.m - Defensive URL Selection

Added nil-checking and fallback in `songsLoaded:`:

```objc
NSString *str = [s highUrl]; // or medUrl/lowUrl based on preference
if (str == nil) str = [s medUrl] ?: [s highUrl] ?: [s lowUrl];

NSURL *url = (str != nil) ? [NSURL URLWithString:str] : nil;
if (url == nil) {
  NSLog(@"No playable URL for song; skipping");
  continue; // Skip this song, don't add to queue
}
```

### 5. ASPlaylist.m - Infinite Skip Protection

Added tracking to detect and stop runaway skips:

**New Fields:**
- `BOOL producedAudio` - Set to YES when `bitrateReady:` fires (real audio flowing)
- `NSInteger consecutiveEmptyFinishes` - Counter for songs that finish without audio

**Logic:**
```objc
- (void)bitrateReady: {
  producedAudio = YES;
  consecutiveEmptyFinishes = 0; // Reset on real audio
}

- (void)playbackStateChanged: {
  if ([stream isDone]) {
    if (!producedAudio) {
      consecutiveEmptyFinishes++;
      if (consecutiveEmptyFinishes >= 3) {
        [self stop];
        // Post ASStreamError instead of continuing
        return;
      }
    }
    [self next];
  }
}

- (void)play {
  producedAudio = NO; // Reset per song
}
```

This converts the infinite skip into a visible error after 3 consecutive empty finishes.

## Unit Tests

### PandoraQualityTests.m

Tests the quality tier selection and fallback logic:

- **Encoding validation** (`encodingIsDecodable`)
  - MP3, AAC, HE-AAC are decodable
  - Unknown codecs (opus, flac) are not
  - Case-insensitive matching

- **Nil-safety**
  - Free accounts with no low tier
  - Pandora One with no low tier
  - Single tier only scenario
  - Empty item handling

- **High tier selection** (the infinite skip root cause)
  - Undecodable codecs don't get selected for High
  - Pandora One 192k MP3 works
  - Free account HE-AAC works after fix

- **Cross-tier fallback**
  - Switching between quality settings never produces nil
  - Legacy additionalAudioUrl array handling

### ASPlaylistSkipTests.m

Tests the infinite skip protection in ASPlaylist:

- **Normal playback**
  - Songs that produce audio and finish advance exactly once
  - No false positives from the guard

- **Infinite skip detection**
  - Multiple zero-audio finishes trigger ASStreamError
  - Stops before exhausting the queue

- **Counter reset**
  - Producing audio clears the empty-finish counter
  - Isolated empty finishes don't immediately trip the guard

Uses a fake AudioStreamer and TestPlaylist subclass to exercise the real logic without Core Audio.

## Testing the Fix

To verify the fix works:

1. Run the unit tests: `PandoraQualityTests` and `ASPlaylistSkipTests`
2. Manual testing:
   - Select "High" quality in preferences
   - Play a station on a free Pandora account
   - Verify songs play normally (no rapid skipping)
   - Verify audio actually plays
3. Edge cases:
   - Toggle between Low/Med/High while playing
   - Test with Pandora One account (192k MP3)
   - Test with free account (HE-AAC)

## Files Modified

1. **Pandora.h** - Exposed testing methods
2. **Pandora.m** - Added encoding check, refactored tier selection
3. **Station.m** - Added defensive nil checks
4. **ASPlaylist.h** - Added tracking fields
5. **ASPlaylist.m** - Added infinite skip protection
6. **AudioStreamer.m** - Added HE-AAC FormatList handling

## Files Created

1. **PandoraQualityTests.m** - Unit tests for quality selection
2. **ASPlaylistSkipTests.m** - Unit tests for skip protection

## Impact

This fix resolves the infinite skip bug completely by addressing all contributing factors:
- HE-AAC audio now decodes properly
- Undecodable codecs are detected and avoided
- Missing tiers fall back gracefully
- Runaway skips are caught and surfaced as errors

The fix is backwards-compatible and preserves existing behavior for working configurations while fixing the broken High quality scenario.
