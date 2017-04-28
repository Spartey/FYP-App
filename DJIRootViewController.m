////
////  DJIRootViewController.m
////  FYP2
////
////  Created by CHEN Liqi on 2017/2/18.
////  Copyright © 2017年 CHEN Liqi. All rights reserved.
////
//

#import "DJIRootViewController.h"
#import <DJISDK/DJISDK.h>
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>
#import "DJIMapController.h"
#import "DJIGSButtonViewController.h"
#import "DJIWaypointConfigViewController.h"
#import "DemoUtility.h"
#import <GLKit/GLKit.h>

#define ENTER_DEBUG_MODE 0

@interface DJIRootViewController ()<DJIGSButtonViewControllerDelegate, MKMapViewDelegate, CLLocationManagerDelegate, DJISDKManagerDelegate, DJIFlightControllerDelegate>

@property (nonatomic, assign) BOOL isEditingPoints;
@property (nonatomic, strong) DJIGSButtonViewController *gsButtonVC;
@property (nonatomic, strong) DJIMapController *mapController;

@property(nonatomic, strong) CLLocationManager* locationManager;
@property(nonatomic, assign) CLLocationCoordinate2D userLocation;
@property(nonatomic, assign) CLLocationCoordinate2D droneLocation;
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;

@property (weak, nonatomic) IBOutlet MKMapView *mapView;
@property (weak, nonatomic) IBOutlet UIView *topBarView;
@property(nonatomic, strong) IBOutlet UILabel* modeLabel;
@property(nonatomic, strong) IBOutlet UILabel* gpsLabel;
@property(nonatomic, strong) IBOutlet UILabel* hsLabel;
@property(nonatomic, strong) IBOutlet UILabel* vsLabel;
@property(nonatomic, strong) IBOutlet UILabel* altitudeLabel;

@property(nonatomic, strong) DJICustomMission* customMission; // consists of 5 waypoint missions
@property(nonatomic, strong) DJICustomMissionStatus* missionStatus;
// @property(nonatomic, strong) DJIWaypointMission* waypointMission;
@property(nonatomic, strong) NSMutableArray<DJIMissionStep *>* waypointSteps;
@property(nonatomic, strong) DJIMissionManager* missionManager;
// @property(nonatomic, strong) DJIWaypointMissionStatus* missionStatus;

@property (weak, nonatomic) IBOutlet UIView *userRegion;
@property (strong, nonatomic) IBOutlet UIPanGestureRecognizer *PanGR;
@property (strong, nonatomic) IBOutlet UIPinchGestureRecognizer *PinchGR;
@property (strong, nonatomic) IBOutlet UIRotationGestureRecognizer *RotateGR;

@property (nonatomic, assign) GLKMatrix3 rotationMatrix;
@property (nonatomic, assign) float rotationAngle; // in radians
@property (nonatomic, assign) float userRegionWidth;
@property (nonatomic, assign) float userRegionHeight;

@property (nonatomic, assign) float flightNormalHeading;


@end



@implementation DJIRootViewController

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self startUpdateLocation];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.locationManager stopUpdatingLocation];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self registerApp];
    self.missionManager = [DJIMissionManager sharedInstance];
    
    [self initUI];
    [self initData];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (BOOL)prefersStatusBarHidden {
    return NO;
}

#pragma mark Init Methods
-(void)initData
{
    self.userLocation = kCLLocationCoordinate2DInvalid;
    self.droneLocation = kCLLocationCoordinate2DInvalid;
    
    self.waypointSteps = [NSMutableArray array];
    
    self.userRegionWidth = 100;
    self.userRegionHeight = 100;
    
    self.mapController = [[DJIMapController alloc] init];
    self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(addWaypoints:)];
    [self.mapView addGestureRecognizer:self.tapGesture];
}

-(void) initUI
{
    self.modeLabel.text = @"N/A";
    self.gpsLabel.text = @"0";
    self.vsLabel.text = @"0.0 M/S";
    self.hsLabel.text = @"0.0 M/S";
    self.altitudeLabel.text = @"0 M";
    
    self.gsButtonVC = [[DJIGSButtonViewController alloc] initWithNibName:@"DJIGSButtonViewController" bundle:[NSBundle mainBundle]];
    [self.gsButtonVC.view setFrame:CGRectMake(0, self.topBarView.frame.origin.y + self.topBarView.frame.size.height, self.gsButtonVC.view.frame.size.width, self.gsButtonVC.view.frame.size.height)];
    self.gsButtonVC.delegate = self;
    [self.view addSubview:self.gsButtonVC.view];
    
    // Set up User Region gesture controlling
    self.PanGR = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panGesture:)];
    [self.PanGR setMaximumNumberOfTouches:1];
    [self.PanGR setMinimumNumberOfTouches:1];
    
    self.PinchGR = [[UIPinchGestureRecognizer alloc]initWithTarget:self action:@selector(pinchGesture:)];
    self.RotateGR = [[UIRotationGestureRecognizer alloc]initWithTarget:self action:@selector(rotationGesture:)];
    
    [self.userRegion addGestureRecognizer:self.PanGR];
    [self.userRegion addGestureRecognizer:self.PinchGR];
    [self.userRegion addGestureRecognizer:self.RotateGR];
    
    [self.userRegion setTag:100];
    [self.view addSubview:self.userRegion];
    
    self.mapView.rotateEnabled = NO;
}

-(void) registerApp
{
    NSString* appKey = @"d44a5359eed0309f1b256fea";
    [DJISDKManager registerApp:appKey withDelegate:self];
}

#pragma mark DJISDKManagerDelegate Methods

- (void)sdkManagerDidRegisterAppWithError:(NSError *_Nullable)error
{
    if (error){
        NSString *registerResult = [NSString stringWithFormat:@"Registration Error:%@", error.description];
        ShowMessage(@"Registration Result", registerResult, nil, @"OK");
    }
    else{
#if ENTER_DEBUG_MODE
        [DJISDKManager enterDebugModeWithDebugId:@"Please Enter Your Debug ID"];
#else
        [DJISDKManager startConnectionToProduct];
#endif
    }
}

- (void)sdkManagerProductDidChangeFrom:(DJIBaseProduct *_Nullable)oldProduct to:(DJIBaseProduct *_Nullable)newProduct
{
    if (newProduct){
        DJIFlightController* flightController = [DemoUtility fetchFlightController];
        if (flightController) {
            flightController.delegate = self;
        }
    }
}

#pragma mark action Methods
- (void)focusMap
{
    if (CLLocationCoordinate2DIsValid(self.droneLocation)) {
        MKCoordinateRegion region = {0};
        region.center = self.droneLocation;
        region.span.latitudeDelta = 0.001;
        region.span.longitudeDelta = 0.001;
        
        [self.mapView setRegion:region animated:YES];
    }
}

#pragma mark CLLocation Methods
-(void) startUpdateLocation
{
    if ([CLLocationManager locationServicesEnabled]) {
        if (self.locationManager == nil) {
            self.locationManager = [[CLLocationManager alloc] init];
            self.locationManager.delegate = self;
            self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
            self.locationManager.distanceFilter = 0.1;
            if ([self.locationManager respondsToSelector:@selector(requestAlwaysAuthorization)]) {
                [self.locationManager requestAlwaysAuthorization];
            }
            [self.locationManager startUpdatingLocation];
        }
    }else
    {
        ShowMessage(@"Location Service is not available", @"", nil, @"OK");
    }
}



/*********************************** add pinpoints to mapview/user region *************************/
- (void) addWaypoints: (int)pathNum
{
    CGPoint point;
    float x_inUserRegion;
    float y_inUserRegion;
    GLKVector3 pointInUserRegion;
    GLKVector3 pointInMapView;
    
    switch (pathNum) {
        case 1:
            x_inUserRegion = - (self.userRegionWidth/2);
            y_inUserRegion = - (self.userRegionHeight/2);
            pointInUserRegion = GLKVector3Make(x_inUserRegion, y_inUserRegion, 1);
            pointInMapView = GLKMatrix3MultiplyVector3(self.rotationMatrix, pointInUserRegion);
            point = CGPointMake(pointInMapView.x + self.userRegion.center.x, pointInMapView.y + self.userRegion.center.y);
            
            [self.mapController addPoint:point withMapView:self.mapView];
            
            for(int i = 1;y_inUserRegion < self.userRegionHeight/2;i++){
                if(i % 2){
                    x_inUserRegion = - x_inUserRegion;
                }else{
                    y_inUserRegion += 20;
                }
                pointInUserRegion = GLKVector3Make(x_inUserRegion, y_inUserRegion, 1);
                pointInMapView = GLKMatrix3MultiplyVector3(self.rotationMatrix, pointInUserRegion);
                point = CGPointMake(pointInMapView.x + self.userRegion.center.x, pointInMapView.y + self.userRegion.center.y);
                [self.mapController addPoint:point withMapView:self.mapView];
            }

            break;
            
        case 2:
            x_inUserRegion = - (self.userRegionWidth/2);
            y_inUserRegion = - (self.userRegionHeight);
            pointInUserRegion = GLKVector3Make(x_inUserRegion, y_inUserRegion, 1);
            pointInMapView = GLKMatrix3MultiplyVector3(self.rotationMatrix, pointInUserRegion);
            point = CGPointMake(pointInMapView.x + self.userRegion.center.x, pointInMapView.y + self.userRegion.center.y);
            
            [self.mapController addPoint:point withMapView:self.mapView];
            
            for(int i = 1;y_inUserRegion < 0;i++){
                if(i % 2){
                    x_inUserRegion = - x_inUserRegion;
                }else{
                    y_inUserRegion += 20;
                }
                pointInUserRegion = GLKVector3Make(x_inUserRegion, y_inUserRegion, 1);
                pointInMapView = GLKMatrix3MultiplyVector3(self.rotationMatrix, pointInUserRegion);
                point = CGPointMake(pointInMapView.x + self.userRegion.center.x, pointInMapView.y + self.userRegion.center.y);
                [self.mapController addPoint:point withMapView:self.mapView];
            }
            
            break;
            
        case 3:
            x_inUserRegion = - (self.userRegionWidth);
            y_inUserRegion = - (self.userRegionHeight/2);
            pointInUserRegion = GLKVector3Make(x_inUserRegion, y_inUserRegion, 1);
            pointInMapView = GLKMatrix3MultiplyVector3(self.rotationMatrix, pointInUserRegion);
            point = CGPointMake(pointInMapView.x + self.userRegion.center.x, pointInMapView.y + self.userRegion.center.y);
            
            [self.mapController addPoint:point withMapView:self.mapView];
            
            for(int i = 1;x_inUserRegion < 0;i++){
                if(i % 2){
                    y_inUserRegion = - y_inUserRegion;
                }else{
                    x_inUserRegion += 20;
                }
                pointInUserRegion = GLKVector3Make(x_inUserRegion, y_inUserRegion, 1);
                pointInMapView = GLKMatrix3MultiplyVector3(self.rotationMatrix, pointInUserRegion);
                point = CGPointMake(pointInMapView.x + self.userRegion.center.x, pointInMapView.y + self.userRegion.center.y);
                [self.mapController addPoint:point withMapView:self.mapView];
            }

            break;
            
        case 4:
            x_inUserRegion = self.userRegionWidth;
            y_inUserRegion = - (self.userRegionHeight/2);
            pointInUserRegion = GLKVector3Make(x_inUserRegion, y_inUserRegion, 1);
            pointInMapView = GLKMatrix3MultiplyVector3(self.rotationMatrix, pointInUserRegion);
            point = CGPointMake(pointInMapView.x + self.userRegion.center.x, pointInMapView.y + self.userRegion.center.y);
            
            [self.mapController addPoint:point withMapView:self.mapView];
            
            for(int i = 1;x_inUserRegion > 0;i++){
                if(i % 2){
                    y_inUserRegion = - y_inUserRegion;
                }else{
                    x_inUserRegion = x_inUserRegion - 20;
                }
                pointInUserRegion = GLKVector3Make(x_inUserRegion, y_inUserRegion, 1);
                pointInMapView = GLKMatrix3MultiplyVector3(self.rotationMatrix, pointInUserRegion);
                point = CGPointMake(pointInMapView.x + self.userRegion.center.x, pointInMapView.y + self.userRegion.center.y);
                [self.mapController addPoint:point withMapView:self.mapView];
            }

            break;
            
        case 5:
            x_inUserRegion = - (self.userRegionWidth/2);
            y_inUserRegion = self.userRegionHeight;
            pointInUserRegion = GLKVector3Make(x_inUserRegion, y_inUserRegion, 1);
            pointInMapView = GLKMatrix3MultiplyVector3(self.rotationMatrix, pointInUserRegion);
            point = CGPointMake(pointInMapView.x + self.userRegion.center.x, pointInMapView.y + self.userRegion.center.y);
            
            [self.mapController addPoint:point withMapView:self.mapView];
            
            for(int i = 1;y_inUserRegion > 0;i++){
                if(i % 2){
                    x_inUserRegion = - x_inUserRegion;
                }else{
                    y_inUserRegion = y_inUserRegion - 20;
                }
                pointInUserRegion = GLKVector3Make(x_inUserRegion, y_inUserRegion, 1);
                pointInMapView = GLKMatrix3MultiplyVector3(self.rotationMatrix, pointInUserRegion);
                point = CGPointMake(pointInMapView.x + self.userRegion.center.x, pointInMapView.y + self.userRegion.center.y);
                [self.mapController addPoint:point withMapView:self.mapView];
            }
            
            break;
            
        default:
            break;
    }
}
/*********************************** add pinpoints to mapview/user region *************************/



- (void)setupBtnActionInGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    self.rotationAngle = atan2f(self.userRegion.transform.b, self.userRegion.transform.a);
    self.rotationMatrix = GLKMatrix3Make(cosf(self.rotationAngle), sinf(self.rotationAngle), 0, -sinf(self.rotationAngle), cosf(self.rotationAngle), 0, 0, 0, 1);
    if(self.rotationAngle > 0){
        self.flightNormalHeading = DEGREE(self.rotationAngle) - 180;
    }else{
        self.flightNormalHeading = DEGREE(self.rotationAngle) + 180;
    }
    
    for(int i=1; i<6; i++){
        [self updateMissionSetting:i];
    }
    
    // [self updateMissionSetting:5];
    
    [self.mapController cleanAllPointsWithMapView:self.mapView];
    
    self.customMission = [[DJICustomMission alloc] initWithSteps:self.waypointSteps];
    
    [self.missionManager prepareMission:self.customMission withProgress:^(float progress) {
        //Do something with progress
    } withCompletion:^(NSError * _Nullable error) {
        if (error){
            NSString* prepareError = [NSString stringWithFormat:@"Prepare Mission failed:%@", error.description];
            ShowMessage(@"", prepareError, nil, @"OK");
        }else {
            ShowMessage(@"", @"Prepare Mission Finished", nil, @"OK");
        }
    }];
}


#pragma mark - DJIGSButtonViewController Delegate Methods

- (void)stopBtnActionInGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    [self.missionManager stopMissionExecutionWithCompletion:^(NSError * _Nullable error) {
        if (error){
            NSString* failedMessage = [NSString stringWithFormat:@"Stop Mission Failed: %@", error.description];
            ShowMessage(@"", failedMessage, nil, @"OK");
        }else
        {
            ShowMessage(@"", @"Stop Mission Finished", nil, @"OK");
        }
    }];
}



/************************* clear the pinpoints ***************************************/
- (void)clearBtnActionInGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    [self.mapController cleanAllPointsWithMapView:self.mapView];
}
/************************* clear the pinpoints ***************************************/




- (void)focusMapBtnActionInGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    [self focusMap];
}




/*********************** set up values of flight/pinpoints info ******************************
- (void)configBtnActionInGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    }
*********************** set up values of flight/pinpoints info ******************************/




- (void)startBtnActionInGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    [self.missionManager startMissionExecutionWithCompletion:^(NSError * _Nullable error) {
        if (error){
            ShowMessage(@"Start Mission Failed", error.description, nil, @"OK");
        }else
        {
            ShowMessage(@"", @"Mission Started", nil, @"OK");
        }
    }];
}



- (void)switchToMode:(DJIGSViewMode)mode inGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    if (mode == DJIGSViewMode_EditMode) {
        [self focusMap];
    }
    
}


- (void)updateMissionSetting:(int)pathNum
{
    switch (pathNum) {
        case 1:
        {
            [self addWaypoints:1];
            
            NSArray* wayPoints = self.mapController.wayPoints;
            if (wayPoints == nil || wayPoints.count < DJIWaypointMissionMinimumWaypointCount) {
                ShowMessage(@"No or not enough waypoints for mission", @"", nil, @"OK");
                return;
            }
            
            DJIWaypointMission* waypointMission;
            if (waypointMission){
                [waypointMission removeAllWaypoints];
            }
            else{
                waypointMission = [[DJIWaypointMission alloc] init];
            }
            
            for (int i = 0; i < wayPoints.count; i++) {
                CLLocation* location = [wayPoints objectAtIndex:i];
                if (CLLocationCoordinate2DIsValid(location.coordinate)) {
                    DJIWaypoint* waypoint = [[DJIWaypoint alloc] initWithCoordinate:location.coordinate];
                    waypoint.altitude = 55;
                    // waypoint.altitude = 5;
                    
                    waypoint.heading = self.flightNormalHeading; // UAV heading of 1st path
                    waypoint.gimbalPitch = -90;
                    
                    // 80% overlap between consecutive photo shooting
                    waypoint.shootPhotoDistanceInterval = 0.2145 * waypoint.altitude;
                    
                    [waypointMission addWaypoint:waypoint];
                }
            }
            
            waypointMission.rotateGimbalPitch = YES; // Set gimbal rotates 90 degree
            waypointMission.maxFlightSpeed = 10; // Set max flight speed
            waypointMission.autoFlightSpeed = 8; // Set auto flight speed
            
            waypointMission.headingMode = 3;
            // 0: Set the headingMode to DJIWaypointMissionHeadingAuto
            // 1: Set the headingMode to DJIWaypointMissionHeadingUsingInitialDirection
            // 2: Set the headingMode to DJIWaypointMissionHeadingControledByRemoteController
            // 3: Set the headingMode to DJIWaypointMissionHeadingUsingWaypointHeading
            // 4: Set the headingMode to DJIWaypointMissionHeadingTowardPointOfInterest
            
            waypointMission.finishedAction = 0;
            // 0: Set the finishAction to DJIWaypointMissionFinishedNoAction
            // 1: Set the finishAction to DJIWaypointMissionFinishedGoHome
            // 2: Set the finishAction to DJIWaypointMissionFinishedAutoLand
            // 3: Set the finishAction to DJIWaypointMissionFinishedGoFirstWaypoint
            // 4: Set the finishAction to DJIWaypointMissionFinishedContinueUntilStop
            
            [self.waypointSteps addObject:[[DJIWaypointStep alloc] initWithWaypointMission:waypointMission]];
        }
            break;
    
        case 2:
        {
            [self.mapController cleanAllPointsWithMapView:self.mapView];
            
            [self addWaypoints:2];
            
            NSArray* wayPoints = self.mapController.wayPoints;
            
            DJIWaypointMission* waypointMission;
            if (waypointMission){
                [waypointMission removeAllWaypoints];
            }
            else{
                waypointMission = [[DJIWaypointMission alloc] init];
            }
            
            for (int i = 0; i < wayPoints.count; i++) {
                CLLocation* location = [wayPoints objectAtIndex:i];
                if (CLLocationCoordinate2DIsValid(location.coordinate)) {
                    DJIWaypoint* waypoint = [[DJIWaypoint alloc] initWithCoordinate:location.coordinate];
                    waypoint.altitude = 55;
                    // waypoint.altitude = 5;
                    
                    waypoint.heading = self.flightNormalHeading;
                    waypoint.gimbalPitch = -45;
                    
                    // 80% overlap between consequtive photo shooting
                    waypoint.shootPhotoDistanceInterval = 0.2145 * waypoint.altitude;
                    
                    [waypointMission addWaypoint:waypoint];
                }
            }
            
            waypointMission.rotateGimbalPitch = YES; // Set gimbal rotates 45 degree
            waypointMission.maxFlightSpeed = 10; // Set max flight speed
            waypointMission.autoFlightSpeed = 8; // Set auto flight speed
            waypointMission.headingMode = 3; // Set to waypoint heading
            waypointMission.finishedAction = 0; // Set to no action
            
            [self.waypointSteps addObject:[[DJIWaypointStep alloc] initWithWaypointMission:waypointMission]];
        }
            break;
        
        case 3:
        {
            [self.mapController cleanAllPointsWithMapView:self.mapView];
            
            [self addWaypoints:3];
            
            NSArray* wayPoints = self.mapController.wayPoints;
            
            DJIWaypointMission* waypointMission;
            if (waypointMission){
                [waypointMission removeAllWaypoints];
            }
            else{
                waypointMission = [[DJIWaypointMission alloc] init];
            }
            
            for (int i = 0; i < wayPoints.count; i++) {
                CLLocation* location = [wayPoints objectAtIndex:i];
                if (CLLocationCoordinate2DIsValid(location.coordinate)) {
                    DJIWaypoint* waypoint = [[DJIWaypoint alloc] initWithCoordinate:location.coordinate];
                    waypoint.altitude = 55;
                    // waypoint.altitude = 5;
                    
                    waypoint.heading = (self.flightNormalHeading < -90 ? self.flightNormalHeading + 270 : self.flightNormalHeading - 90);
                    waypoint.gimbalPitch = -45;
                    
                    // 80% overlap between consequtive photo shooting
                    waypoint.shootPhotoDistanceInterval = 0.2145 * waypoint.altitude;
                    
                    [waypointMission addWaypoint:waypoint];
                }
            }
            
            waypointMission.rotateGimbalPitch = YES; // Set gimbal rotates 45 degree
            waypointMission.maxFlightSpeed = 10; // Set max flight speed
            waypointMission.autoFlightSpeed = 8; // Set auto flight speed
            waypointMission.headingMode = 3; // Set to waypoint heading
            waypointMission.finishedAction = 0; // Set to no action
            
            [self.waypointSteps addObject:[[DJIWaypointStep alloc] initWithWaypointMission:waypointMission]];
        }
            break;

        case 4:
        {
            [self.mapController cleanAllPointsWithMapView:self.mapView];
            
            [self addWaypoints:4];
            
            NSArray* wayPoints = self.mapController.wayPoints;
            
            DJIWaypointMission* waypointMission;
            if (waypointMission){
                [waypointMission removeAllWaypoints];
            }
            else{
                waypointMission = [[DJIWaypointMission alloc] init];
            }
            
            for (int i = 0; i < wayPoints.count; i++) {
                CLLocation* location = [wayPoints objectAtIndex:i];
                if (CLLocationCoordinate2DIsValid(location.coordinate)) {
                    DJIWaypoint* waypoint = [[DJIWaypoint alloc] initWithCoordinate:location.coordinate];
                    waypoint.altitude = 55;
                    // waypoint.altitude = 5;
                    
                    waypoint.heading = (self.flightNormalHeading < -90 ? self.flightNormalHeading + 90 : self.flightNormalHeading - 270);
                    waypoint.gimbalPitch = -45;
                    
                    // 80% overlap between consequtive photo shooting
                    waypoint.shootPhotoDistanceInterval = 0.2145 * waypoint.altitude;
                    
                    [waypointMission addWaypoint:waypoint];
                }
            }
            
            waypointMission.rotateGimbalPitch = YES; // Set gimbal rotates 45 degree
            waypointMission.maxFlightSpeed = 10; // Set max flight speed
            waypointMission.autoFlightSpeed = 8; // Set auto flight speed
            waypointMission.headingMode = 3; // Set to waypoint heading
            waypointMission.finishedAction = 0; // Set to no action
            
            [self.waypointSteps addObject:[[DJIWaypointStep alloc] initWithWaypointMission:waypointMission]];
        }
            break;
            
        case 5:
        {
            [self.mapController cleanAllPointsWithMapView:self.mapView];

            [self addWaypoints:5];
            
            NSArray* wayPoints = self.mapController.wayPoints;
            
            DJIWaypointMission* waypointMission;
            if (waypointMission){
                [waypointMission removeAllWaypoints];
            }
            else{
                waypointMission = [[DJIWaypointMission alloc] init];
            }
            
            for (int i = 0; i < wayPoints.count; i++) {
                CLLocation* location = [wayPoints objectAtIndex:i];
                if (CLLocationCoordinate2DIsValid(location.coordinate)) {
                    DJIWaypoint* waypoint = [[DJIWaypoint alloc] initWithCoordinate:location.coordinate];
                    waypoint.altitude = 55;
                    // waypoint.altitude = 5;
                    
                    waypoint.heading = (self.flightNormalHeading < 0 ? self.flightNormalHeading + 180 : self.flightNormalHeading - 180);
                    waypoint.gimbalPitch = -45;
                    
                    // 80% overlap between consequtive photo shooting
                    waypoint.shootPhotoDistanceInterval = 0.2145 * waypoint.altitude;
                    
                    [waypointMission addWaypoint:waypoint];
                }
            }
            
            waypointMission.rotateGimbalPitch = YES; // Set gimbal rotates 45 degree
            waypointMission.maxFlightSpeed = 10; // Set max flight speed
            waypointMission.autoFlightSpeed = 8; // Set auto flight speed
            waypointMission.headingMode = 3; // Set to waypoint heading
            waypointMission.finishedAction = 1; // Set to go home
            
            [self.waypointSteps addObject:[[DJIWaypointStep alloc] initWithWaypointMission:waypointMission]];
        }
            break;
            
        default:
            break;
    }
}



/***********************change the value of isEditingPoint to enable pinpoint*************************
- (void)add:(UIButton *)button withActionInGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    if (self.isEditingPoints) {
        self.isEditingPoints = NO;
    }else
    {
        self.isEditingPoints = YES;
    }
}
***********************change the value of isEditingPoint to enable pinpoint*************************/




#pragma mark - CLLocationManagerDelegate
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
    CLLocation* location = [locations lastObject];
    self.userLocation = location.coordinate;
}

#pragma mark MKMapViewDelegate Method
- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id <MKAnnotation>)annotation
{
    if ([annotation isKindOfClass:[MKPointAnnotation class]]) {
        MKPinAnnotationView* pinView = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"Pin_Annotation"];
        pinView.pinTintColor = [UIColor purpleColor];
        return pinView;
        
    }else if ([annotation isKindOfClass:[DJIAircraftAnnotation class]])
    {
        DJIAircraftAnnotationView* annoView = [[DJIAircraftAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"Aircraft_Annotation"];
        ((DJIAircraftAnnotation*)annotation).annotationView = annoView;
        return annoView;
    }
    
    return nil;
}

#pragma mark DJIFlightControllerDelegate

- (void)flightController:(DJIFlightController *)fc didUpdateSystemState:(DJIFlightControllerCurrentState *)state
{
    self.droneLocation = state.aircraftLocation;
    
    self.modeLabel.text = state.flightModeString;
    self.gpsLabel.text = [NSString stringWithFormat:@"%d", state.satelliteCount];
    self.vsLabel.text = [NSString stringWithFormat:@"%0.1f M/S",state.velocityZ];
    
    float speed = sqrtf(state.velocityX*state.velocityX + state.velocityY*state.velocityY);
    self.hsLabel.text = [NSString stringWithFormat:@"%0.1f M/S",speed];
    self.altitudeLabel.text = [NSString stringWithFormat:@"%0.1f M",state.altitude];
    
    [self.mapController updateAircraftLocation:self.droneLocation withMapView:self.mapView];
    double radianYaw = RADIAN(state.attitude.yaw);
    [self.mapController updateAircraftHeading:radianYaw];
}


// Gesture Selector Implementation
- (void)panGesture:(UIPanGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateChanged ||
        sender.state == UIGestureRecognizerStateEnded) {
        //注意，这里取得的参照坐标系是该对象的上层View的坐标。
        CGPoint offset = [sender translationInView:self.view];
        UIView *draggableObj = [self.view viewWithTag:100];
        //通过计算偏移量来设定draggableObj的新坐标
        [draggableObj setCenter:CGPointMake(draggableObj.center.x + offset.x, draggableObj.center.y + offset.y)];
        //初始化sender中的坐标位置。如果不初始化，移动坐标会一直积累起来。
        [sender setTranslation:CGPointMake(0, 0) inView:self.view];
    }
}

- (void)pinchGesture:(UIPinchGestureRecognizer *)pinchGesture
{
    pinchGesture.view.transform = CGAffineTransformScale(pinchGesture.view.transform, pinchGesture.scale, pinchGesture.scale);
    
    [pinchGesture setScale:1.0];
    
    self.userRegionWidth = self.userRegion.frame.size.width;
    self.userRegionHeight = self.userRegion.frame.size.height;
    
}

- (void)rotationGesture:(UIRotationGestureRecognizer *)rotationGesture
{
    rotationGesture.view.transform = CGAffineTransformRotate(rotationGesture.view.transform, rotationGesture.rotation);
    
    rotationGesture.rotation = 0;
}

@end
