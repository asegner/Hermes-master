#import <XCTest/XCTest.h>
#import <AudioToolbox/AudioToolbox.h>

#import "AudioStreamer+Testing.h"

@interface AudioStreamer ()
- (void)handlePropertyChangeForQueue:(AudioQueueRef)inAQ
                          propertyID:(AudioQueuePropertyID)inID;
@end

static void HMSAudioQueueOutputCallback(__unused void *inUserData,
                                        __unused AudioQueueRef inAQ,
                                        __unused AudioQueueBufferRef inBuffer) {
}

@interface AudioStreamerStartupTests : XCTestCase
@end

@implementation AudioStreamerStartupTests

- (AudioQueueRef)createTestAudioQueue {
  AudioStreamBasicDescription asbd = {0};
  asbd.mSampleRate = 44100.0;
  asbd.mFormatID = kAudioFormatLinearPCM;
  asbd.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
  asbd.mBitsPerChannel = 16;
  asbd.mChannelsPerFrame = 1;
  asbd.mBytesPerFrame = 2;
  asbd.mFramesPerPacket = 1;
  asbd.mBytesPerPacket = 2;

  AudioQueueRef queue = NULL;
  OSStatus err = AudioQueueNewOutput(&asbd,
                                     HMSAudioQueueOutputCallback,
                                     NULL,
                                     NULL,
                                     NULL,
                                     0,
                                     &queue);
  XCTAssertEqual(err, noErr);
  return queue;
}

- (void)testSpuriousIsRunningCallbackIgnoredBeforeQueueStarts {
  NSURL *url = [NSURL URLWithString:@"https://example.com/test.mp3"];
  AudioStreamer *streamer = [AudioStreamer streamWithURL:url];
  AudioQueueRef queue = [self createTestAudioQueue];
  XCTAssertNotEqual(queue, NULL);

  [streamer setStateDispatchSynchronousForTesting:YES];
  [streamer setInternalStateForTesting:AS_WAITING_FOR_DATA];
  [streamer setAudioQueueForTesting:queue];
  [streamer setHasAudioQueueStartedForTesting:NO];

  [streamer handlePropertyChangeForQueue:queue propertyID:kAudioQueueProperty_IsRunning];

  XCTAssertEqual([streamer internalStateForTesting], AS_WAITING_FOR_DATA);

  AudioQueueDispose(queue, true);
  [streamer setAudioQueueForTesting:NULL];
}

- (void)testIsRunningCallbackStillTransitionsToDoneAfterQueueStarted {
  NSURL *url = [NSURL URLWithString:@"https://example.com/test.mp3"];
  AudioStreamer *streamer = [AudioStreamer streamWithURL:url];
  AudioQueueRef queue = [self createTestAudioQueue];
  XCTAssertNotEqual(queue, NULL);

  [streamer setStateDispatchSynchronousForTesting:YES];
  [streamer setInternalStateForTesting:AS_PLAYING];
  [streamer setAudioQueueForTesting:queue];
  [streamer setHasAudioQueueStartedForTesting:YES];

  [streamer handlePropertyChangeForQueue:queue propertyID:kAudioQueueProperty_IsRunning];

  XCTAssertEqual([streamer internalStateForTesting], AS_DONE);

  AudioQueueDispose(queue, true);
  [streamer setAudioQueueForTesting:NULL];
}

@end
