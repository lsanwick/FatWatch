//
//  WeightFormatters.h
//  EatWatch
//
//  Created by Benjamin Ragheb on 7/26/08.
//  Copyright 2008 Benjamin Ragheb. All rights reserved.
//

#import <UIKit/UIKit.h>


@interface WeightFormatters : NSObject {

}

+ (NSArray *)weightUnitNames;
+ (void)selectWeightUnitAtIndex:(NSUInteger)index;
+ (NSArray *)energyUnitNames;
+ (void)selectEnergyUnitAtIndex:(NSUInteger)index;
+ (NSArray *)scaleIncrementNames;
+ (void)selectScaleIncrementAtIndex:(NSUInteger)index;

+ (float)scaleIncrement;
+ (NSFormatter *)weightFormatter;
+ (NSString *)stringForWeight:(float)weightLbs;
+ (NSFormatter *)weightChangeFormatter;
+ (NSString *)stringForWeightChange:(float)deltaLbs;
+ (NSFormatter *)energyChangePerDayFormatter;
+ (NSString *)energyStringForWeightPerDay:(float)lbsPerDay;
+ (NSFormatter *)weightChangePerWeekFormatter;
+ (NSString *)weightStringForWeightPerDay:(float)lbsPerDay;
+ (NSNumberFormatter *)exportWeightFormatter;

@end