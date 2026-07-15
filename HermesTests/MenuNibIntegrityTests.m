#import <XCTest/XCTest.h>

@interface MenuNibIntegrityTests : XCTestCase

@end

@implementation MenuNibIntegrityTests

- (NSXMLDocument *)mainMenuDocumentWithError:(NSError **)error {
  NSString *testFilePath = [NSString stringWithUTF8String:__FILE__];
  NSURL *projectRootURL = [[NSURL fileURLWithPath:testFilePath] URLByDeletingLastPathComponent].URLByDeletingLastPathComponent;
  NSURL *mainMenuURL = [projectRootURL URLByAppendingPathComponent:@"Resources/Base.lproj/MainMenu.xib"];
  NSData *data = [NSData dataWithContentsOfURL:mainMenuURL options:0 error:error];
  if (data == nil) {
    return nil;
  }
  return [[NSXMLDocument alloc] initWithData:data options:0 error:error];
}

- (NSString *)destinationForFileOwnerOutlet:(NSString *)property document:(NSXMLDocument *)document {
  NSString *xpath = [NSString stringWithFormat:@"//customObject[@id='-2']/connections/outlet[@property='%@']/@destination", property];
  NSError *error = nil;
  NSArray<NSXMLNode *> *nodes = [document nodesForXPath:xpath error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(nodes.count, 1, @"Expected exactly one %@ outlet on NSApplication File's Owner", property);
  return nodes.firstObject.stringValue;
}

- (void)testMainMenuNibConnectsApplicationMenuOutlets {
  NSError *error = nil;
  NSXMLDocument *document = [self mainMenuDocumentWithError:&error];
  XCTAssertNotNil(document);
  XCTAssertNil(error);

  XCTAssertEqualObjects([self destinationForFileOwnerOutlet:@"mainMenu" document:document], @"29");
  XCTAssertEqualObjects([self destinationForFileOwnerOutlet:@"servicesMenu" document:document], @"130");
  XCTAssertEqualObjects([self destinationForFileOwnerOutlet:@"windowsMenu" document:document], @"24");
}

- (void)testMainMenuNibKeepsTopLevelMenuItems {
  NSError *error = nil;
  NSXMLDocument *document = [self mainMenuDocumentWithError:&error];
  XCTAssertNotNil(document);
  XCTAssertNil(error);

  NSArray<NSXMLNode *> *topLevelItems = [document nodesForXPath:@"//menu[@id='29']/items/menuItem" error:&error];
  XCTAssertNil(error);

  NSArray<NSString *> *expectedTitles = @[@"ApolloGene", @"File", @"Edit", @"View", @"Pandora", @"Window", @"Help"];
  NSMutableArray<NSString *> *actualTitles = [[NSMutableArray alloc] initWithCapacity:topLevelItems.count];
  for (NSXMLNode *item in topLevelItems) {
    NSString *title = [[(NSXMLElement *)item attributeForName:@"title"] stringValue];
    if (title != nil) {
      [actualTitles addObject:title];
    }
  }

  for (NSString *title in expectedTitles) {
    XCTAssertTrue([actualTitles containsObject:title], @"MainMenu.xib is missing top-level menu item %@", title);
  }
}

- (void)testMainMenuNibDoesNotForceAquaAppearance {
  NSError *error = nil;
  NSXMLDocument *document = [self mainMenuDocumentWithError:&error];
  XCTAssertNotNil(document);
  XCTAssertNil(error);

  NSArray<NSXMLNode *> *forcedAquaElements =
      [document nodesForXPath:@"//*[@appearanceType='aqua']" error:&error];
  XCTAssertNil(error);
  XCTAssertEqual(forcedAquaElements.count, 0,
                 @"MainMenu.xib should inherit the system appearance");
}

@end
