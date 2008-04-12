//
//  EatWatchAppDelegate.h
//  EatWatch
//
//  Created by Benjamin Ragheb on 3/15/08.
//  Copyright Benjamin Ragheb 2008. All rights reserved.
//

#import <UIKit/UIKit.h>

@class Database;

@interface EatWatchAppDelegate : NSObject <UIApplicationDelegate> {
	Database *database;
    UIWindow *window;
    UITabBarController *tabBarController;
}

@property (nonatomic, retain) UIWindow *window;
@property (nonatomic, retain) UITabBarController *tabBarController;

@end
