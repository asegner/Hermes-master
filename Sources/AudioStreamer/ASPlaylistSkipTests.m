//
//  ASPlaylistSkipTests.m
//  Hermes
//
//  Unit tests for the infinite play/skip protection in ASPlaylist.
//
//  Background: an undecodable audio URL (e.g. an unhandled codec on the High
//  tier under the macOS 11 audio pipeline) opens, produces zero decodable
//  packets, and reports AS_DONE immediately. The playlist used to interpret
//  that as "song finished" and call next, racing through the whole station at
//  full speed. These tests verify:
//
//   1. A normal song that produces audio and then finishes advances exactly
//      once (no false positive from the guard).
//   2. A run of zero-audio "finishes" is detected and the playlist stops with
//      an ASStreamError instead of skipping forever.
//   3. The empty-finish counter resets once a song actually produces audio.
//
//  We avoid real Core Audio by substituting a fake AudioStreamer and a test
//  subclass of ASPlaylist that installs it and counts next/stop. The real
//  playbackStateChanged: / bitrateReady: logic under test is exercised
//  unmodified.
//

#import <XCTest/XCTest.h>
#import "AudioStreamer/ASPlaylist.h"
#import "AudioStreamer/AudioStreamer.h"

#pragma mark - Fake stream

@interface FakeAudioStreamer : AudioStreamer
@property (nonatomic) BOOL fakeDone;
@property (nonatomic) AudioStreamerErrorCode fakeError;
@property (nonatomic) BOOL started;
@end

@implementation FakeAudioStreamer
- (void)start { self.started = YES; }
- (void)stop { /* no-op for test */ }
- (BOOL)isDone { return self.fakeDone; }
- (BOOL)isPlaying { return !self.fakeDone; }
- (AudioStreamerErrorCode)errorCode { return self.fakeError; }
- (BOOL)setVolume:(double)volume { return YES; }
- (BOOL)progress:(double *)ret { if (ret) *ret = 0; return YES; }
@end

#pragma mark - Test playlist

@interface TestPlaylist : ASPlaylist
@property (nonatomic, strong) FakeAudioStreamer *fakeStream;
@property (nonatomic) NSInteger nextCount;
@property (nonatomic) NSInteger stopCount;
@property (nonatomic) BOOL sawStreamError;
@end

@implementation TestPlaylist

// Install our fake instead of a real AudioStreamer, but keep posting the same
// notifications the real setAudioStream posts so the observers under test wire
// up identically.
- (void)setAudioStream {
  self.fakeStream = [[FakeAudioStreamer alloc] init];
  // Use KVC to assign the private `stream` ivar that the superclass reads.
  [self setValue:self.fakeStream forKey:@"stream"];

  [[NSNotificationCenter defaultCenter]
        postNotificationName:ASCreatedNewStream
                      object:self
                    userInfo:@{@"stream": self.fakeStream}];
  [[NSNotificationCenter defaultCenter]
    addObserver:self selector:@selector(playbackStateChanged:)
           name:ASStatusChangedNotification object:self.fakeStream];
  [[NSNotificationCenter defaultCenter]
    addObserver:self selector:@selector(bitrateReady:)
           name:ASBitrateReadyNotification object:self.fakeStream];
}

- (void)next { self.nextCount++; [super next]; }
- (void)stop { self.stopCount++; [super stop]; }

// Drive the real playbackStateChanged: by posting the status notification the
// way AudioStreamer would.
- (void)signalStatusChanged {
  [[NSNotificationCenter defaultCenter]
        postNotificationName:ASStatusChangedNotification
                      object:self.fakeStream];
}

// Drive the real bitrateReady: ("real audio is now flowing").
- (void)signalBitrateReady {
  [[NSNotificationCenter defaultCenter]
        postNotificationName:ASBitrateReadyNotification
                      object:self.fakeStream];
}

@end

#pragma mark - Tests

@interface ASPlaylistSkipTests : XCTestCase
@end

@implementation ASPlaylistSkipTests {
  TestPlaylist *playlist;
  NSInteger streamErrorCount;
  id observer;
}

- (void)setUp {
  [super setUp];
  playlist = [[TestPlaylist alloc] init];
  streamErrorCount = 0;
  observer = [[NSNotificationCenter defaultCenter]
    addObserverForName:ASStreamError object:playlist queue:nil
    usingBlock:^(NSNotification *n) { self->streamErrorCount++; }];

  // Seed the queue with several songs.
  for (int i = 0; i < 10; i++) {
    NSURL *u = [NSURL URLWithString:[NSString stringWithFormat:@"http://song/%d", i]];
    [playlist addSong:u play:NO];
  }
}

- (void)tearDown {
  [[NSNotificationCenter defaultCenter] removeObserver:observer];
  [super tearDown];
}

// A song that produces audio and then ends should advance exactly once and
// never trip the empty-finish guard.
- (void)testNormalFinishAdvancesOnce {
  [playlist play];                 // opens song 0
  [playlist signalBitrateReady];   // real audio flows
  playlist.fakeStream.fakeDone = YES;
  [playlist signalStatusChanged];  // song 0 ends normally

  // performSelectorOnMainThread is async; spin the runloop briefly.
  [self spinRunLoop];

  XCTAssertEqual(playlist.nextCount, 1, @"normal finish should advance once");
  XCTAssertEqual(streamErrorCount, 0, @"normal finish must not error");
}

// A run of songs that each "finish" with zero audio must NOT skip forever; the
// guard should stop after ASMaxConsecutiveEmptyFinishes and post ASStreamError.
- (void)testZeroAudioFinishesStopInsteadOfInfiniteSkip {
  [playlist play];   // opens song 0

  // Simulate up to 8 consecutive empty finishes. The guard must fire well
  // before exhausting the queue.
  for (int i = 0; i < 8; i++) {
    // NOTE: no bitrateReady -> producedAudio stays NO for each song.
    playlist.fakeStream.fakeDone = YES;
    [playlist signalStatusChanged];
    [self spinRunLoop];
    if (streamErrorCount > 0) break;
  }

  XCTAssertGreaterThan(streamErrorCount, 0,
      @"infinite-skip guard must surface an error");
  // It must have given up well before churning through all 10 songs.
  XCTAssertLessThan(playlist.nextCount, 5,
      @"guard must stop the runaway skip quickly, not after the whole station");
}

// If a song eventually produces audio, the empty-finish counter resets, so a
// later isolated empty finish does not immediately trip the guard.
- (void)testProducingAudioResetsEmptyFinishCounter {
  [playlist play];   // song 0

  // Two empty finishes (below the threshold of 3).
  for (int i = 0; i < 2; i++) {
    playlist.fakeStream.fakeDone = YES;
    [playlist signalStatusChanged];
    [self spinRunLoop];
  }
  XCTAssertEqual(streamErrorCount, 0, @"two empties should not trip the guard");

  // Next song actually plays -> counter resets.
  playlist.fakeStream.fakeDone = NO;
  [playlist signalBitrateReady];
  playlist.fakeStream.fakeDone = YES;
  [playlist signalStatusChanged];   // normal finish
  [self spinRunLoop];

  XCTAssertEqual(streamErrorCount, 0, @"a real play resets the counter");

  // Two more empties after the reset still should not trip (counter restarted).
  for (int i = 0; i < 2; i++) {
    playlist.fakeStream.fakeDone = YES;
    [playlist signalStatusChanged];
    [self spinRunLoop];
  }
  XCTAssertEqual(streamErrorCount, 0,
      @"counter must have reset after the song produced audio");
}

#pragma mark - util

- (void)spinRunLoop {
  [[NSRunLoop currentRunLoop] runUntilDate:
      [NSDate dateWithTimeIntervalSinceNow:0.02]];
}

@end
