#import <XCTest/XCTest.h>

#import "PlaybackController.h"
#import "Pandora/Station.h"

@interface PlaybackController (StationModesTesting)
- (void)configureStationModesUI;
- (void)populateStationModeMenuWithEntries:(NSArray<NSDictionary *> *)entries;
@end

@interface FakePlaybackStationModeService : NSObject <PlaybackStationModeService>
@property (nonatomic, assign) BOOL authenticated;
@property (nonatomic, assign) BOOL setModeResult;
@property (nonatomic, strong) Station *fetchedStation;
@property (nonatomic, strong) Station *setStation;
@property (nonatomic, copy) NSString *setModeIdentifier;
@end

@implementation FakePlaybackStationModeService

- (instancetype)init {
  if ((self = [super init])) {
    _authenticated = YES;
    _setModeResult = YES;
  }
  return self;
}

- (BOOL)isAuthenticated {
  return self.authenticated;
}

- (BOOL)fetchStationModesForStation:(Station *)station {
  self.fetchedStation = station;
  return YES;
}

- (BOOL)setMode:(NSString *)modeIdentifier forStation:(Station *)station {
  self.setModeIdentifier = modeIdentifier;
  self.setStation = station;
  return self.setModeResult;
}

@end

@interface TestStationForModes : Station
@property (nonatomic, assign) NSUInteger clearSongListCount;
@end

@implementation TestStationForModes

- (void)clearSongList {
  self.clearSongListCount++;
}

@end

@interface TestPlaybackControllerForModes : PlaybackController
@property (nonatomic, assign) NSUInteger nextCount;
@end

@implementation TestPlaybackControllerForModes

- (IBAction)next:(id)sender {
  self.nextCount++;
}

@end

@interface StationModesTests : XCTestCase
@end

@implementation StationModesTests

- (TestPlaybackControllerForModes *)controllerWithService:(FakePlaybackStationModeService **)serviceOut {
  TestPlaybackControllerForModes *controller = [[TestPlaybackControllerForModes alloc] init];
  FakePlaybackStationModeService *service = [[FakePlaybackStationModeService alloc] init];
  controller.stationModeService = service;
  [controller setValue:[[NSTextField alloc] init] forKey:@"stationModeLabel"];
  [controller setValue:[[NSMenu alloc] initWithTitle:@"Stations"] forKey:@"stationModesMenu"];
  [controller setValue:[[NSMenuItem alloc] initWithTitle:@"Stations" action:nil keyEquivalent:@""] forKey:@"stationModesMenuItem"];
  [controller configureStationModesUI];
  if (serviceOut) {
    *serviceOut = service;
  }
  return controller;
}

- (void)testPopulatesSelectableModeMenuItems {
  TestPlaybackControllerForModes *controller = [self controllerWithService:nil];
  NSArray *entries = @[
    @{@"identifier": @"0", @"name": @"My Station", @"current": @YES},
    @{@"identifier": @"42", @"name": @"Crowd Faves", @"current": @NO}
  ];

  [controller populateStationModeMenuWithEntries:entries];

  NSMenu *menu = [controller valueForKey:@"stationModesMenu"];
  NSMenuItem *topLevelItem = [controller valueForKey:@"stationModesMenuItem"];
  NSTextField *label = [controller valueForKey:@"stationModeLabel"];

  XCTAssertEqual(menu.numberOfItems, 2);
  XCTAssertTrue(topLevelItem.enabled);
  XCTAssertEqualObjects(label.stringValue, @"Station Mode: My Station");

  NSMenuItem *currentItem = [menu itemAtIndex:0];
  NSMenuItem *otherItem = [menu itemAtIndex:1];
  XCTAssertEqualObjects(currentItem.title, @"My Station");
  XCTAssertEqualObjects(currentItem.representedObject, @"0");
  XCTAssertEqual(currentItem.action, @selector(selectStationMode:));
  XCTAssertEqual(currentItem.target, controller);
  XCTAssertTrue(currentItem.enabled);
  XCTAssertEqual(currentItem.state, NSControlStateValueOn);

  XCTAssertEqualObjects(otherItem.title, @"Crowd Faves");
  XCTAssertEqualObjects(otherItem.representedObject, @"42");
  XCTAssertEqual(otherItem.state, NSControlStateValueOff);
}

- (void)testSelectingModeCallsServiceAndRefreshesPlaybackQueue {
  FakePlaybackStationModeService *service = nil;
  TestPlaybackControllerForModes *controller = [self controllerWithService:&service];
  TestStationForModes *station = [[TestStationForModes alloc] init];
  station.stationId = @"station-1";
  [controller setValue:station forKey:@"playing"];

  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Crowd Faves"
                                                action:@selector(selectStationMode:)
                                         keyEquivalent:@""];
  item.representedObject = @"42";

  [controller selectStationMode:item];

  XCTAssertEqualObjects(service.setModeIdentifier, @"42");
  XCTAssertEqual(service.setStation, station);
  XCTAssertEqual(station.clearSongListCount, 1U);
  XCTAssertEqual(controller.nextCount, 1U);

  NSTextField *label = [controller valueForKey:@"stationModeLabel"];
  XCTAssertEqualObjects(label.stringValue, @"Station Mode: Loading…");
}

- (void)testSelectingModeDoesNotRefreshQueueWhenRequestDoesNotStart {
  FakePlaybackStationModeService *service = nil;
  TestPlaybackControllerForModes *controller = [self controllerWithService:&service];
  service.setModeResult = NO;
  TestStationForModes *station = [[TestStationForModes alloc] init];
  station.stationId = @"station-1";
  [controller setValue:station forKey:@"playing"];

  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Crowd Faves"
                                                action:@selector(selectStationMode:)
                                         keyEquivalent:@""];
  item.representedObject = @"42";

  [controller selectStationMode:item];

  XCTAssertEqualObjects(service.setModeIdentifier, @"42");
  XCTAssertEqual(station.clearSongListCount, 0U);
  XCTAssertEqual(controller.nextCount, 0U);
}

- (void)testValidationRequiresAuthenticationPlayingStationAndModeIdentifier {
  FakePlaybackStationModeService *service = nil;
  TestPlaybackControllerForModes *controller = [self controllerWithService:&service];
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Crowd Faves"
                                                action:@selector(selectStationMode:)
                                         keyEquivalent:@""];
  item.representedObject = @"42";

  XCTAssertFalse([controller validateUserInterfaceItem:item]);

  Station *station = [[Station alloc] init];
  station.stationId = @"station-1";
  [controller setValue:station forKey:@"playing"];
  XCTAssertTrue([controller validateUserInterfaceItem:item]);

  item.representedObject = @"";
  XCTAssertFalse([controller validateUserInterfaceItem:item]);

  item.representedObject = @"42";
  service.authenticated = NO;
  XCTAssertFalse([controller validateUserInterfaceItem:item]);
}

@end
