#import <React/RCTLog.h>
#import "RNGoogleSignin.h"
#import "RNGSPromiseWrapper.h"

@interface RNGoogleSignin ()

@property (nonatomic) RNGSPromiseWrapper *promiseWrapper;


@end

@implementation RNGoogleSignin

RCT_EXPORT_MODULE();

static NSString *const ASYNC_OP_IN_PROGRESS = @"ASYNC_OP_IN_PROGRESS";
static NSString *const PLAY_SERVICES_NOT_AVAILABLE = @"PLAY_SERVICES_NOT_AVAILABLE";

// The key in `GoogleService-Info.plist` client id.
// For more see https://developers.google.com/identity/sign-in/ios/start
static NSString *const kClientIdKey = @"CLIENT_ID";

- (NSDictionary *)constantsToExport
{
  return @{
           @"BUTTON_SIZE_ICON": @(kGIDSignInButtonStyleIconOnly),
           @"BUTTON_SIZE_STANDARD": @(kGIDSignInButtonStyleStandard),
           @"BUTTON_SIZE_WIDE": @(kGIDSignInButtonStyleWide),
           @"BUTTON_COLOR_LIGHT": @(kGIDSignInButtonColorSchemeLight),
           @"BUTTON_COLOR_DARK": @(kGIDSignInButtonColorSchemeDark),
           @"SIGN_IN_CANCELLED": [@(kGIDSignInErrorCodeCanceled) stringValue],
           @"SIGN_IN_REQUIRED": [@(kGIDSignInErrorCodeHasNoAuthInKeychain) stringValue],
           @"IN_PROGRESS": ASYNC_OP_IN_PROGRESS,
           PLAY_SERVICES_NOT_AVAILABLE: PLAY_SERVICES_NOT_AVAILABLE // this never happens on iOS
           };
}

+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

- (dispatch_queue_t)methodQueue
{
  return dispatch_get_main_queue();
}

- (instancetype)init {
  self = [super init];
  if (self != nil) {
    self.promiseWrapper = [[RNGSPromiseWrapper alloc] init];
  }
  return self;
}

RCT_EXPORT_METHOD(configure:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  NSString *path;
#ifdef DEBUG
    NSLog(@"[FIREBASE] Development mode.");
    path = [[NSBundle mainBundle] pathForResource:@"GoogleService-Info" ofType:@"plist" inDirectory:@"Debug"];
#else
    NSLog(@"[FIREBASE] Production mode.");
    path = [[NSBundle mainBundle] pathForResource:@"GoogleService-Info" ofType:@"plist" inDirectory:@"Release"];
#endif

  if (!path) {
    RCTLogError(@"RNGoogleSignin: Missing GoogleService-Info.plist");
    reject(@"INTERNAL_MISSING_CONFIG", @"Missing GoogleService-Info.plist", nil);
    return;
  }

  NSDictionary *plist = [[NSDictionary alloc] initWithContentsOfFile:path];

  [GIDSignIn sharedInstance].delegate = self;
  [GIDSignIn sharedInstance].uiDelegate = self;
  [GIDSignIn sharedInstance].scopes = options[@"scopes"];
  [GIDSignIn sharedInstance].shouldFetchBasicProfile = YES; // email, profile
  [GIDSignIn sharedInstance].clientID = plist[kClientIdKey];
  
  if (options[@"hostedDomain"]) {
    [GIDSignIn sharedInstance].hostedDomain = options[@"hostedDomain"];
  }
  if (options[@"webClientId"]) {
    [GIDSignIn sharedInstance].serverClientID = options[@"webClientId"];
  }
  
  resolve(@YES);
}

RCT_REMAP_METHOD(signInSilently,
                 currentUserAsyncResolve:(RCTPromiseResolveBlock)resolve
                 currentUserAsyncReject:(RCTPromiseRejectBlock)reject)
{
  BOOL wasPromiseSet = [self.promiseWrapper setPromiseWithInProgressCheck:resolve rejecter:reject];
  if (!wasPromiseSet) {
    [self rejectWithAsyncOperationStillInProgress: reject];
    return;
  }
  [[GIDSignIn sharedInstance] signInSilently];
}

RCT_REMAP_METHOD(signIn,
                 signInResolve:(RCTPromiseResolveBlock)resolve
                 signInReject:(RCTPromiseRejectBlock)reject)
{
  BOOL wasPromiseSet = [self.promiseWrapper setPromiseWithInProgressCheck:resolve rejecter:reject];
  if (!wasPromiseSet) {
    [self rejectWithAsyncOperationStillInProgress: reject];
    return;
  }
  [[GIDSignIn sharedInstance] signIn];
}

RCT_REMAP_METHOD(signOut,
                 signOutResolve:(RCTPromiseResolveBlock)resolve
                 signOutReject:(RCTPromiseRejectBlock)reject)
{
  [[GIDSignIn sharedInstance] signOut];
  resolve(@YES);
}

RCT_REMAP_METHOD(revokeAccess,
                 revokeAccessResolve:(RCTPromiseResolveBlock)resolve
                 revokeAccessReject:(RCTPromiseRejectBlock)reject)
{
  BOOL wasPromiseSet = [self.promiseWrapper setPromiseWithInProgressCheck:resolve rejecter:reject];
  if (!wasPromiseSet) {
    [self rejectWithAsyncOperationStillInProgress: reject];
    return;
  }
  [[GIDSignIn sharedInstance] disconnect];
}

RCT_REMAP_METHOD(isSignedIn,
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  BOOL isSignedIn = [[GIDSignIn sharedInstance] hasAuthInKeychain];
  resolve([NSNumber numberWithBool:isSignedIn]);
}

- (void)signIn:(GIDSignIn *)signIn didSignInForUser:(GIDGoogleUser *)user withError:(NSError *)error {
  if (error) {
    [self rejectWithSigninError: error];
  } else {
    [self resolveWithUserDetails: user];
  }
}

- (void)resolveWithUserDetails: (GIDGoogleUser *) user {
  NSURL *imageURL = user.profile.hasImage ? [user.profile imageURLWithDimension:120] : nil;
  
  NSDictionary *userInfo = @{
                             @"id": user.userID,
                             @"name": user.profile.name ? user.profile.name : [NSNull null],
                             @"givenName": user.profile.givenName ? user.profile.givenName : [NSNull null],
                             @"familyName": user.profile.familyName ? user.profile.familyName : [NSNull null],
                             @"photo": imageURL ? imageURL.absoluteString : [NSNull null],
                             @"email": user.profile.email
                             };
  
  NSDictionary *params = @{
                           @"user": userInfo,
                           @"idToken": user.authentication.idToken,
                           @"serverAuthCode": user.serverAuthCode ? user.serverAuthCode : [NSNull null],
                           @"accessToken": user.authentication.accessToken,
                           @"scopes": user.accessibleScopes,
                           @"accessTokenExpirationDate": [NSNumber numberWithDouble:user.authentication.accessTokenExpirationDate.timeIntervalSinceNow] // Deprecated as of 2018-08-06
                           };
  
  [self.promiseWrapper resolve:params];
}

- (void)rejectWithSigninError: (NSError *) error {
  NSString * errorMessage = @"Unknown error when signing in.";
  switch (error.code) {
    case kGIDSignInErrorCodeUnknown:
      errorMessage = @"Unknown error when signing in.";
      break;
    case kGIDSignInErrorCodeKeychain:
      errorMessage = @"A problem reading or writing to the application keychain.";
      break;
    case kGIDSignInErrorCodeNoSignInHandlersInstalled:
      errorMessage = @"No appropriate applications are installed on the device which can handle sign-in. Both webview and switching to browser have both been disabled.";
      break;
    case kGIDSignInErrorCodeHasNoAuthInKeychain:
      errorMessage = @"The user has never signed in before with the given scopes, or they have since signed out.";
      break;
    case kGIDSignInErrorCodeCanceled:
      errorMessage = @"The user canceled the sign in request.";
      break;
  }
  [self.promiseWrapper reject:errorMessage withError:error];
}

- (void)signIn:(GIDSignIn *)signIn didDisconnectWithUser:(GIDGoogleUser *)user withError:(NSError *)error {
  if (error) {
    [self.promiseWrapper reject:@"Error when revoking access." withError:error];
    return;
  }
  
  [self.promiseWrapper resolve:(@YES)];
}

- (void)signIn:(GIDSignIn *)signIn presentViewController:(UIViewController *)viewController {
  [RCTPresentedViewController() presentViewController:viewController animated:true completion:nil];
}

- (void)signIn:(GIDSignIn *)signIn dismissViewController:(UIViewController *)viewController {
  [viewController dismissViewControllerAnimated:true completion:nil];
}

- (void)rejectWithAsyncOperationStillInProgress: (RCTPromiseRejectBlock)reject {
  reject(ASYNC_OP_IN_PROGRESS, @"cannot set promise - some async operation is still in progress", nil);
}

+ (BOOL)application:(UIApplication *)application openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication annotation: (id)annotation {
  
  return [[GIDSignIn sharedInstance] handleURL:url
                             sourceApplication:sourceApplication
                                    annotation:annotation];
}

@end
