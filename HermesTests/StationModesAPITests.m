#import <XCTest/XCTest.h>

#import "Notifications.h"
#import "Pandora/Pandora.h"
#import "Pandora/Station.h"

@interface Pandora (StationModesAPITesting)
- (BOOL)sendRequest:(PandoraRequest *)request;
@end

@interface CapturingStationModesPandora : Pandora
@property (nonatomic, strong) PandoraRequest *lastRequest;
@property (nonatomic, strong) NSDictionary *response;
@end

@implementation CapturingStationModesPandora

- (BOOL)isAuthenticated {
  return YES;
}

- (BOOL)sendRequest:(PandoraRequest *)request {
  self.lastRequest = request;
  if (request.callback != nil && self.response != nil) {
    request.callback(self.response);
  }
  return YES;
}

@end

@interface StationModesAPITests : XCTestCase
@end

@implementation StationModesAPITests

- (Station *)stationWithId:(NSString *)stationId {
  Station *station = [[Station alloc] init];
  station.stationId = stationId;
  return station;
}

- (void)testFetchStationModesRejectsMissingStationId {
  CapturingStationModesPandora *pandora = [[CapturingStationModesPandora alloc] init];
  Station *station = [self stationWithId:nil];

  XCTAssertFalse([pandora fetchStationModesForStation:station]);
  XCTAssertNil(pandora.lastRequest);
}

- (void)testFetchStationModesSendsGetAvailableModesRequest {
  CapturingStationModesPandora *pandora = [[CapturingStationModesPandora alloc] init];
  Station *station = [self stationWithId:@"station-1"];

  XCTAssertTrue([pandora fetchStationModesForStation:station]);

  XCTAssertEqualObjects(pandora.lastRequest.method, @"interactiveradio.v1.getAvailableModes");
  XCTAssertEqualObjects(pandora.lastRequest.request[@"stationId"], @"station-1");
}

- (void)testSetModeRejectsMissingInputs {
  CapturingStationModesPandora *pandora = [[CapturingStationModesPandora alloc] init];

  XCTAssertFalse([pandora setMode:@"1" forStation:nil]);
  XCTAssertFalse([pandora setMode:@"" forStation:[self stationWithId:@"station-1"]]);
  XCTAssertFalse([pandora setMode:@"1" forStation:[self stationWithId:nil]]);
  XCTAssertNil(pandora.lastRequest);
}

- (void)testSetModeSendsSetAndGetAvailableModesRequest {
  CapturingStationModesPandora *pandora = [[CapturingStationModesPandora alloc] init];
  Station *station = [self stationWithId:@"station-1"];

  XCTAssertTrue([pandora setMode:@"42" forStation:station]);

  XCTAssertEqualObjects(pandora.lastRequest.method, @"interactiveradio.v1.setAndGetAvailableModes");
  XCTAssertEqualObjects(pandora.lastRequest.request[@"stationId"], @"station-1");
  XCTAssertEqualObjects(pandora.lastRequest.request[@"modeId"], @"42");
}

- (void)testSetModePostsUpdatedStationModesNotification {
  CapturingStationModesPandora *pandora = [[CapturingStationModesPandora alloc] init];
  Station *station = [self stationWithId:@"station-1"];
  pandora.response = @{
    @"stat": @"ok",
    @"result": @{
      @"availableModes": @[
        @{@"modeId": @"0", @"modeName": @"My Station"},
        @{@"modeId": @"42", @"modeName": @"Crowd Faves"}
      ],
      @"currentModeId": @"42"
    }
  };

  XCTestExpectation *expectation = [self expectationWithDescription:@"Updated modes notification"];
  id observer = [[NSNotificationCenter defaultCenter] addObserverForName:PandoraDidLoadStationModesNotification
                                                                  object:station
                                                                   queue:nil
                                                              usingBlock:^(NSNotification *note) {
    NSArray *modes = note.userInfo[@"modes"];
    XCTAssertEqualObjects(note.userInfo[@"stationId"], @"station-1");
    XCTAssertEqualObjects(note.userInfo[@"currentModeId"], @"42");
    XCTAssertEqual([modes count], 2U);
    XCTAssertEqualObjects(modes[1][@"identifier"], @"42");
    XCTAssertEqualObjects(modes[1][@"name"], @"Crowd Faves");
    XCTAssertEqualObjects(modes[1][@"current"], @YES);
    [expectation fulfill];
  }];

  XCTAssertTrue([pandora setMode:@"42" forStation:station]);

  [self waitForExpectations:@[expectation] timeout:1.0];
  [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

@end
