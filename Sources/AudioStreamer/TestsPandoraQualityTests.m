//
//  PandoraQualityTests.m
//  HermesTests
//
//  Unit tests for audio-quality tier selection in Pandora getPlaylist parsing.
//
//  Covers the bug where High quality death-spiralled (infinite play/skip) and
//  where Low/High could resolve to a nil URL. Exercises every quality tier at
//  every bitrate/format combination Pandora is known to return, for both
//  Pandora One and free accounts.
//
//  The tests drive +[Pandora populateAudioUrlsForSong:fromItem:] (the real
//  parsing/selection logic, extracted for testability) plus the per-tier URL
//  pick that Station performs, so the full path "JSON item -> chosen URL" is
//  validated without needing a live network or audio device.
//

#import <XCTest/XCTest.h>
#import "Pandora/Pandora.h"
#import "Pandora/Song.h"
#import "PreferencesController.h"

@interface PandoraQualityTests : XCTestCase
@end

@implementation PandoraQualityTests

#pragma mark - Helpers

/* Build a getPlaylist "items" entry. Pass nil for any tier to omit it. Each
   tier dict mirrors Pandora's audioUrlMap shape: encoding/bitrate/audioUrl. */
- (NSDictionary *)itemWithHigh:(NSDictionary *)high
                           med:(NSDictionary *)med
                           low:(NSDictionary *)low
                    additional:(NSArray *)additional {
  NSMutableDictionary *map = [NSMutableDictionary dictionary];
  if (high) map[@"highQuality"] = high;
  if (med)  map[@"mediumQuality"] = med;
  if (low)  map[@"lowQuality"] = low;

  NSMutableDictionary *item = [NSMutableDictionary dictionary];
  item[@"audioUrlMap"] = map;
  if (additional) item[@"additionalAudioUrl"] = additional;
  return item;
}

- (NSDictionary *)tierWithEncoding:(NSString *)enc
                           bitrate:(NSString *)bitrate
                               url:(NSString *)url {
  NSMutableDictionary *t = [NSMutableDictionary dictionary];
  if (enc)     t[@"encoding"] = enc;
  if (bitrate) t[@"bitrate"]  = bitrate;
  if (url)     t[@"audioUrl"] = url;
  return t;
}

/* Mirror of the tier-selection that Station.songsLoaded: performs, including
   its defensive cross-tier fallback. Returns the URL string that would be
   queued for the given quality, or nil if none. */
- (NSString *)selectedURLForSong:(Song *)song quality:(int)quality {
  NSString *str = nil;
  switch (quality) {
    case QUALITY_HIGH: str = song.highUrl; break;
    case QUALITY_LOW:  str = song.lowUrl;  break;
    case QUALITY_MED:
    default:           str = song.medUrl;  break;
  }
  if (str == nil) str = song.medUrl ?: song.highUrl ?: song.lowUrl;
  return str;
}

- (Song *)songFromItem:(NSDictionary *)item {
  Song *song = [[Song alloc] init];
  [Pandora populateAudioUrlsForSong:song fromItem:item];
  return song;
}

#pragma mark - encodingIsDecodable

- (void)testMP3IsDecodable {
  XCTAssertTrue([Pandora encodingIsDecodable:@"mp3"]);
}

- (void)testAACPlusIsDecodableAfterHEAACReenable {
  // HE-AAC ("aacplus") must now be considered decodable since the FormatList /
  // SBR path was re-enabled in AudioStreamer.
  XCTAssertTrue([Pandora encodingIsDecodable:@"aacplus"]);
  XCTAssertTrue([Pandora encodingIsDecodable:@"aac"]);
}

- (void)testNilOrEmptyEncodingAssumedDecodable {
  XCTAssertTrue([Pandora encodingIsDecodable:nil]);
  XCTAssertTrue([Pandora encodingIsDecodable:@""]);
}

- (void)testUnknownEncodingIsNotDecodable {
  // A future/unrecognized codec must degrade rather than risk infinite skip.
  XCTAssertFalse([Pandora encodingIsDecodable:@"opus"]);
  XCTAssertFalse([Pandora encodingIsDecodable:@"flac-weird-future"]);
}

- (void)testEncodingIsCaseInsensitive {
  XCTAssertTrue([Pandora encodingIsDecodable:@"MP3"]);
  XCTAssertTrue([Pandora encodingIsDecodable:@"AACPlus"]);
}

#pragma mark - No tier ever resolves to nil (the crash / dead-playlist bug)

- (void)testFreeAccountAllTiersNonNil {
  // Free account: no low tier provided, high is HE-AAC 64k, med is AAC 64k.
  Song *song = [self songFromItem:
    [self itemWithHigh:[self tierWithEncoding:@"aacplus" bitrate:@"64" url:@"http://high/heaac"]
                   med:[self tierWithEncoding:@"aacplus" bitrate:@"64" url:@"http://med/aac"]
                   low:nil
            additional:nil]];

  XCTAssertNotNil(song.highUrl);
  XCTAssertNotNil(song.medUrl);
  XCTAssertNotNil(song.lowUrl, @"low must fall back, never nil");

  // Every quality setting must produce a queueable URL.
  XCTAssertNotNil([self selectedURLForSong:song quality:QUALITY_HIGH]);
  XCTAssertNotNil([self selectedURLForSong:song quality:QUALITY_MED]);
  XCTAssertNotNil([self selectedURLForSong:song quality:QUALITY_LOW]);
}

- (void)testPandoraOneNoLowTierStillNonNil {
  // Pandora One: 192k MP3 high, 64k AAC med, NO low (Pandora omits it).
  Song *song = [self songFromItem:
    [self itemWithHigh:[self tierWithEncoding:@"mp3" bitrate:@"192" url:@"http://high/mp3"]
                   med:[self tierWithEncoding:@"aacplus" bitrate:@"64" url:@"http://med/aac"]
                   low:nil
            additional:nil]];

  XCTAssertEqualObjects(song.highUrl, @"http://high/mp3");
  XCTAssertNotNil(song.lowUrl, @"low must fall back to med/high, never nil");
  XCTAssertNotNil([self selectedURLForSong:song quality:QUALITY_LOW]);
}

- (void)testSingleTierOnlyFillsAll {
  // Pathological: only a low tier present. All settings must still play.
  Song *song = [self songFromItem:
    [self itemWithHigh:nil
                   med:nil
                   low:[self tierWithEncoding:@"aacplus" bitrate:@"32" url:@"http://low/only"]
            additional:nil]];

  XCTAssertEqualObjects(song.lowUrl, @"http://low/only");
  XCTAssertEqualObjects(song.medUrl, @"http://low/only");
  XCTAssertEqualObjects(song.highUrl, @"http://low/only");
  XCTAssertEqualObjects([self selectedURLForSong:song quality:QUALITY_HIGH], @"http://low/only");
}

- (void)testEmptyItemYieldsNilButDoesNotCrash {
  // No audio data at all. Population must not throw; selection returns nil so
  // Station can skip the song rather than queue nil.
  Song *song = [self songFromItem:@{}];
  XCTAssertNil(song.highUrl);
  XCTAssertNil(song.medUrl);
  XCTAssertNil(song.lowUrl);
  XCTAssertNil([self selectedURLForSong:song quality:QUALITY_HIGH]);
}

#pragma mark - High tier: the infinite-skip root cause

- (void)testFreeAccountHighDoesNotSelectUndecodableHEAAC_whenMarkedUndecodable {
  // If a station ever reports an explicitly undecodable encoding on high, High
  // must NOT resolve to it (that produced zero-packet streams -> infinite skip).
  Song *song = [self songFromItem:
    [self itemWithHigh:[self tierWithEncoding:@"opus" bitrate:@"256" url:@"http://high/undecodable"]
                   med:[self tierWithEncoding:@"aacplus" bitrate:@"64" url:@"http://med/aac"]
                   low:[self tierWithEncoding:@"aacplus" bitrate:@"32" url:@"http://low/aac"]
            additional:nil]];

  XCTAssertNotEqualObjects(song.highUrl, @"http://high/undecodable",
                           @"High must not select an undecodable codec");
  // High should have degraded to the medium (known-good) URL.
  XCTAssertEqualObjects([self selectedURLForSong:song quality:QUALITY_HIGH], @"http://med/aac");
}

- (void)testPandoraOneHighSelects192MP3 {
  Song *song = [self songFromItem:
    [self itemWithHigh:[self tierWithEncoding:@"mp3" bitrate:@"192" url:@"http://high/mp3-192"]
                   med:[self tierWithEncoding:@"aacplus" bitrate:@"64" url:@"http://med/aac"]
                   low:[self tierWithEncoding:@"aacplus" bitrate:@"32" url:@"http://low/aac"]
            additional:nil]];
  XCTAssertEqualObjects([self selectedURLForSong:song quality:QUALITY_HIGH], @"http://high/mp3-192");
}

- (void)testFreeAccountHighSelectsDecodableHEAAC {
  // With HE-AAC re-enabled, a free-account HE-AAC high tier is now a valid pick.
  Song *song = [self songFromItem:
    [self itemWithHigh:[self tierWithEncoding:@"aacplus" bitrate:@"64" url:@"http://high/heaac-64"]
                   med:[self tierWithEncoding:@"aacplus" bitrate:@"64" url:@"http://med/aac-64"]
                   low:[self tierWithEncoding:@"aacplus" bitrate:@"32" url:@"http://low/aac-32"]
            additional:nil]];
  NSString *high = [self selectedURLForSong:song quality:QUALITY_HIGH];
  XCTAssertNotNil(high);
  // Either the HE-AAC high URL (decodable) or a clean degrade -- never nil and
  // never an undecodable codec.
  XCTAssertTrue([high isEqualToString:@"http://high/heaac-64"] ||
                [high isEqualToString:@"http://med/aac-64"]);
}

#pragma mark - Switching between tiers (the original regression)

- (void)testSwitchingAcrossAllTiersAlwaysYieldsURL {
  // Simulate a user toggling Low <-> Med <-> High on the same fetched song.
  // None of the transitions may produce a nil URL (that froze playback before).
  Song *song = [self songFromItem:
    [self itemWithHigh:[self tierWithEncoding:@"mp3" bitrate:@"192" url:@"http://h"]
                   med:[self tierWithEncoding:@"aacplus" bitrate:@"64" url:@"http://m"]
                   low:nil   // free-ish: no low
            additional:nil]];

  int order[] = { QUALITY_MED, QUALITY_HIGH, QUALITY_LOW, QUALITY_HIGH,
                  QUALITY_MED, QUALITY_LOW, QUALITY_HIGH };
  for (int i = 0; i < (int)(sizeof(order)/sizeof(order[0])); i++) {
    NSString *url = [self selectedURLForSong:song quality:order[i]];
    XCTAssertNotNil(url, @"quality %d produced nil URL on switch step %d", order[i], i);
  }
}

#pragma mark - additionalAudioUrl (legacy array form) bitrates

- (void)testAdditionalAudioUrlArrayMapsTiers {
  // Legacy "HTTP_32_AACPLUS_ADTS,HTTP_64_AACPLUS_ADTS,HTTP_128_MP3" returns a
  // 3-element array: [low, med, high].
  Song *song = [self songFromItem:
    [self itemWithHigh:nil med:nil low:nil
            additional:@[@"http://a/32", @"http://a/64", @"http://a/128"]]];
  XCTAssertEqualObjects(song.lowUrl,  @"http://a/32");
  XCTAssertEqualObjects(song.medUrl,  @"http://a/64");
  XCTAssertEqualObjects(song.highUrl, @"http://a/128");
}

- (void)testAdditionalAudioUrlShortArrayFallsBack {
  // Only two elements present: [low, med], no high. High must fall back.
  Song *song = [self songFromItem:
    [self itemWithHigh:nil med:nil low:nil
            additional:@[@"http://a/32", @"http://a/64"]]];
  XCTAssertEqualObjects(song.lowUrl,  @"http://a/32");
  XCTAssertEqualObjects(song.medUrl,  @"http://a/64");
  XCTAssertNotNil(song.highUrl, @"high must fall back to med, never nil");
  XCTAssertEqualObjects([self selectedURLForSong:song quality:QUALITY_HIGH], @"http://a/64");
}

- (void)testAudioUrlMapOverridesLowerAdditionalBitrate {
  // additional gives 128 MP3 high; audioUrlMap gives 192 MP3 high -> 192 wins.
  Song *song = [self songFromItem:
    [self itemWithHigh:[self tierWithEncoding:@"mp3" bitrate:@"192" url:@"http://map/192"]
                   med:nil low:nil
            additional:@[@"http://a/32", @"http://a/64", @"http://a/128"]]];
  XCTAssertEqualObjects(song.highUrl, @"http://map/192");
}

@end
