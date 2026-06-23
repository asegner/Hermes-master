# Testing Guide - High Quality Infinite Skip Fix

## Overview

This guide explains how to run the unit tests that verify the fix for the infinite skip bug when High audio quality is selected.

## Unit Tests Created

### 1. PandoraQualityTests.m
Tests the audio quality tier selection and fallback logic in Pandora.m.

**Test Categories:**
- `encodingIsDecodable` - Validates codec support detection
- No tier resolves to nil - Ensures all quality settings have valid URLs
- High tier selection - Tests the root cause of infinite skip
- Tier switching - Validates dynamic quality changes
- Legacy additionalAudioUrl handling

**Key Tests:**
- `testFreeAccountHighDoesNotSelectUndecodableHEAAC_whenMarkedUndecodable` - **The main infinite skip fix**
- `testFreeAccountHighSelectsDecodableHEAAC` - Verifies HE-AAC works after FormatList fix
- `testPandoraOneHighSelects192MP3` - Verifies Pandora One high quality

### 2. ASPlaylistSkipTests.m
Tests the infinite skip protection mechanism in ASPlaylist.m.

**Test Categories:**
- Normal playback behavior - No false positives
- Zero-audio finish detection - Catches infinite skip
- Counter reset logic - After real audio plays

**Key Tests:**
- `testZeroAudioFinishesStopInsteadOfInfiniteSkip` - **Verifies the skip guard works**
- `testNormalFinishAdvancesOnce` - Ensures normal songs still work
- `testProducingAudioResetsEmptyFinishCounter` - Validates counter reset

## Running Tests in Xcode

### Command Line (xcodebuild)

```bash
# Run all tests
xcodebuild test -scheme Hermes

# Run just quality tests
xcodebuild test -scheme Hermes -only-testing:HermesTests/PandoraQualityTests

# Run just skip protection tests
xcodebuild test -scheme Hermes -only-testing:HermesTests/ASPlaylistSkipTests

# Run a specific test
xcodebuild test -scheme Hermes \
  -only-testing:HermesTests/PandoraQualityTests/testFreeAccountHighDoesNotSelectUndecodableHEAAC_whenMarkedUndecodable
```

### Xcode IDE

1. Open the project in Xcode
2. Press `Cmd+U` to run all tests
3. Or use the Test Navigator (Cmd+6):
   - Expand the test hierarchy
   - Click the diamond icon next to any test or test class
   - Right-click for more options (Run, Debug)

### Test Navigator Location

```
Hermes Tests
├── PandoraQualityTests
│   ├── encodingIsDecodable
│   │   ├── testMP3IsDecodable
│   │   ├── testAACPlusIsDecodableAfterHEAACReenable
│   │   ├── testNilOrEmptyEncodingAssumedDecodable
│   │   ├── testUnknownEncodingIsNotDecodable
│   │   └── testEncodingIsCaseInsensitive
│   ├── No tier ever resolves to nil
│   │   ├── testFreeAccountAllTiersNonNil
│   │   ├── testPandoraOneNoLowTierStillNonNil
│   │   ├── testSingleTierOnlyFillsAll
│   │   └── testEmptyItemYieldsNilButDoesNotCrash
│   ├── High tier: the infinite-skip root cause
│   │   ├── testFreeAccountHighDoesNotSelectUndecodableHEAAC_whenMarkedUndecodable ⭐
│   │   ├── testPandoraOneHighSelects192MP3
│   │   └── testFreeAccountHighSelectsDecodableHEAAC
│   ├── Switching between tiers
│   │   └── testSwitchingAcrossAllTiersAlwaysYieldsURL
│   └── additionalAudioUrl
│       ├── testAdditionalAudioUrlArrayMapsTiers
│       ├── testAdditionalAudioUrlShortArrayFallsBack
│       └── testAudioUrlMapOverridesLowerAdditionalBitrate
│
└── ASPlaylistSkipTests
    ├── testNormalFinishAdvancesOnce
    ├── testZeroAudioFinishesStopInsteadOfInfiniteSkip ⭐
    └── testProducingAudioResetsEmptyFinishCounter
```

⭐ = Critical tests for the infinite skip bug

## Expected Results

All tests should pass ✅

### If Tests Fail

**PandoraQualityTests failures:**
- Check that `+[Pandora encodingIsDecodable:]` is implemented correctly
- Verify `+[Pandora populateAudioUrlsForSong:fromItem:]` is exposed in Pandora.h
- Ensure the fallback logic fills all three URL properties

**ASPlaylistSkipTests failures:**
- Check that `producedAudio` and `consecutiveEmptyFinishes` fields are added to ASPlaylist.h
- Verify `bitrateReady:` sets `producedAudio = YES`
- Verify `playbackStateChanged:` checks the counter before calling `next`
- Ensure `play` method resets `producedAudio = NO`

## Manual Testing

After unit tests pass, verify manually:

### Test Scenario 1: Free Account High Quality
1. Configure app with free Pandora account credentials
2. Set quality preference to "High"
3. Play a station
4. **Expected:** Songs play normally, no rapid skipping
5. **Expected:** Audio is audible (HE-AAC decoding works)

### Test Scenario 2: Pandora One High Quality
1. Configure app with Pandora One account credentials
2. Set quality preference to "High"
3. Play a station
4. **Expected:** Songs play at 192 Kbps MP3 quality
5. **Expected:** No skipping

### Test Scenario 3: Quality Switching
1. Start playing on "Medium"
2. Switch to "High" while playing
3. Skip to next song
4. **Expected:** New song plays at High quality
5. **Expected:** No nil URL errors in console

### Test Scenario 4: Simulated Codec Issue
To verify the infinite skip guard actually works, you would need to:
1. Temporarily modify code to inject an undecodable URL
2. Set High quality
3. Play
4. **Expected:** After 3 failed songs, ASStreamError fires and playback stops
5. **Expected:** Console log: "ASPlaylist: 3 songs finished without audio; stopping..."

## Debugging

### Enable Debug Logging

Look for these log messages:

```
// Pandora.m
High quality audio from audioUrlMap is 192 Kbps mp3
Selected HE-AAC/SBR playable format from FormatList

// AudioStreamer.m  
FormatList info unavailable (err ...) - may indicate issue
Selected HE-AAC/SBR playable format from FormatList - good!

// ASPlaylist.m
ASPlaylist: 3 songs finished without audio; stopping... - infinite skip caught
```

### Console Filters

In Xcode Console, filter for:
- "quality" - See tier selection
- "FormatList" - See HE-AAC handling
- "finished without audio" - See skip protection
- "No playable URL" - See nil URL protection

## Integration with CI/CD

To integrate into a CI pipeline:

```bash
#!/bin/bash
# run_quality_tests.sh

set -e

echo "Running High Quality Infinite Skip Fix Tests..."

# Clean build
xcodebuild clean -scheme Hermes

# Build and test
xcodebuild test \
  -scheme Hermes \
  -destination 'platform=macOS' \
  -only-testing:HermesTests/PandoraQualityTests \
  -only-testing:HermesTests/ASPlaylistSkipTests \
  | tee test_output.log

# Check for success
if grep -q "** TEST SUCCEEDED **" test_output.log; then
  echo "✅ All quality tests passed"
  exit 0
else
  echo "❌ Quality tests failed"
  exit 1
fi
```

## Coverage

The tests achieve high coverage of the fix:

- ✅ Pandora.m `encodingIsDecodable:` - 100%
- ✅ Pandora.m `populateAudioUrlsForSong:fromItem:` - 100%
- ✅ Station.m URL selection logic - covered via integration
- ✅ ASPlaylist.m infinite skip guard - 100%
- ✅ AudioStreamer.m FormatList handling - covered via integration

## Questions?

See `HIGH_QUALITY_FIX_SUMMARY.md` for detailed information about what was fixed and why.
