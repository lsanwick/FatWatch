/*
 * EWGoal.m
 * Created by Benjamin Ragheb on 8/19/08.
 * Copyright 2015 Heroic Software Inc
 *
 * This file is part of FatWatch.
 *
 * FatWatch is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * FatWatch is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with FatWatch.  If not, see <http://www.gnu.org/licenses/>.
 */

#import "EWDBMonth.h"
#import "EWDBIterator.h"
#import "EWDatabase.h"
#import "EWGoal.h"
#import "EWWeightFormatter.h"
#import "NSUserDefaults+EWAdditions.h"


static const NSTimeInterval kSecondsPerDay = 60 * 60 * 24;
static const float kDefaultWeightChangePerDay = 0.5f / 7; // half lb / week


NSString * const EWGoalDidChangeNotification = @"EWGoalDidChange";
float gGoalBandHeight;
float gGoalBandHalfHeight;


static NSString * const kGoalWeightKey = @"GoalWeight";
static NSString * const kGoalDateKey = @"GoalDate"; // stored as MonthDay
static NSString * const kGoalRateKey = @"GoalRate"; // stored as weight lbs/day


@implementation EWGoal
{
	EWDatabase *database;
}

#pragma mark Class Methods


+ (void)fixHeightIfNeeded {
	static NSString *kHeightFixAppliedKey = @"EWFixedBug0000017";
	NSUserDefaults *uds = [NSUserDefaults standardUserDefaults];
	
	if ([uds boolForKey:kHeightFixAppliedKey]) return;
	
	// To fix a stupid bug where all height values were offset by 1 cm,
	// causing weird results when measuring in inches.
	if ([uds heightIncrement] > 0.01f) {
		float height = [uds height];
		float error = fmodf(height, 0.0254f);
		if (fabsf(error - 0.01f) < 0.0001f) {
			[uds setHeight:(height - 0.01f)];
			NSLog(@"Bug 0000017: Height adjusted from %f to %f", height, [uds height]);
		}
	}

	[uds setBool:YES forKey:kHeightFixAppliedKey];
}


+ (void)upgradeDefaultsIfNeededDatabase:(EWDatabase *)db {
	static NSString * const kOldGoalStartDateKey = @"GoalStartDate";
	static NSString * const kOldGoalWeightChangePerDayKey = @"GoalWeightChangePerDay";
	
	NSUserDefaults *uds = [NSUserDefaults standardUserDefaults];
	
	// check if we need to upgrade
	if ([uds objectForKey:kOldGoalWeightChangePerDayKey] == nil) return;

	NSTimeInterval t = [uds doubleForKey:kOldGoalStartDateKey];
	NSDate *startDate = [NSDate dateWithTimeIntervalSinceReferenceDate:t];
	float changePerDay = [uds floatForKey:kOldGoalWeightChangePerDayKey];

	float startWeight;
	{
		EWMonthDay md = EWMonthDayNext(EWMonthDayFromDate(startDate));
		EWDBMonth *dbm = [db getDBMonth:EWMonthDayGetMonth(md)];
		startWeight = [dbm inputTrendOnDay:EWMonthDayGetDay(md)];
		if (startWeight == 0) {
			startWeight = [db earliestWeight];
		}
	}
	
	float goalWeight = [uds floatForKey:kGoalWeightKey];

	if (startWeight > 0 && goalWeight > 0) {
		NSTimeInterval seconds = (goalWeight - startWeight) / changePerDay * kSecondsPerDay;
		NSDate *goalDate = [startDate dateByAddingTimeInterval:seconds];
		[uds setInteger:EWMonthDayFromDate(goalDate) forKey:kGoalDateKey];
	} else {
		[uds removeObjectForKey:kGoalWeightKey];
		[uds removeObjectForKey:kGoalDateKey];
	}
	
	[uds removeObjectForKey:kOldGoalStartDateKey];
	[uds removeObjectForKey:kOldGoalWeightChangePerDayKey];
}


+ (void)initBandHeight {
	NSUserDefaults *uds = [NSUserDefaults standardUserDefaults];
	if ([uds weightUnit] == EWWeightUnitKilograms) {
		gGoalBandHeight = 2.2f / kKilogramsPerPound;
	} else {
		gGoalBandHeight = 5.0f;
	}
	gGoalBandHalfHeight = 0.5f * gGoalBandHeight;
}


+ (void)deleteGoal {
	NSUserDefaults *uds = [NSUserDefaults standardUserDefaults];
	[uds removeObjectForKey:kGoalWeightKey];
	[uds removeObjectForKey:kGoalDateKey];
	[[NSNotificationCenter defaultCenter] postNotificationName:EWGoalDidChangeNotification object:self];
}


+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key {
	NSSet *keyPaths = [super keyPathsForValuesAffectingValueForKey:key];
	
	// endWeight is independent
	// endDate is handled manually
	// weightChangePerDay is handled manually
	
	if ([key isEqualToString:@"endWeightNumber"]) {
		keyPaths = [keyPaths setByAddingObject:@"endWeight"];
	}
	else if ([key isEqualToString:@"endWeight"]) {
		keyPaths = [keyPaths setByAddingObject:@"endWeightNumber"];
	}
	
	return keyPaths;
}


#pragma mark Instance


- (id)initWithDatabase:(EWDatabase *)db {
	static BOOL firstInstance = YES;
	
	NSParameterAssert(db != nil);

	if (firstInstance) {
		[EWGoal fixHeightIfNeeded];
		[EWGoal upgradeDefaultsIfNeededDatabase:db];
		[EWGoal initBandHeight];
		firstInstance = NO;
	}
	
	if ((self = [super init])) {
		database = db;
	}
	return self;
}




#pragma mark Helper Methods


- (float)currentWeight {
	float w = [database latestWeight];
	if (w > 0) return w;

	// this means the database is empty, so we'll just return the goal weight
	return self.endWeight;
}


- (NSDate *)endDateWithWeightChangePerDay:(float)weightChangePerDay {
	NSTimeInterval seconds;
	
	@synchronized (self) {
		float totalWeightChange = (self.endWeight - [self currentWeight]);
		seconds = totalWeightChange / weightChangePerDay * kSecondsPerDay;
	}
	return [NSDate dateWithTimeIntervalSinceNow:seconds];
}


#pragma mark Properties


- (EWGoalState)state {
	NSUserDefaults *uds = [NSUserDefaults standardUserDefaults];
	@synchronized (self) {
		// Allow goal weight to be present, but zero; for easier automation testing.
		if ([uds floatForKey:kGoalWeightKey] <= 0) {
			return EWGoalStateUndefined;
		}
		if ([uds objectForKey:kGoalRateKey] != nil) {
			return EWGoalStateFixedRate;
		}
		if ([uds objectForKey:kGoalDateKey] != nil) {
			return EWGoalStateFixedDate;
		}
	}
	return EWGoalStateInvalid;
}


#pragma mark -


- (BOOL)isDefined {
	return (self.state != EWGoalStateUndefined);
}


#pragma mark -


- (float)endWeight {
	NSUserDefaults *uds = [NSUserDefaults standardUserDefaults];
	@synchronized (self) {
		return [uds floatForKey:kGoalWeightKey];
	}
	return 0;
}


- (void)setEndWeight:(float)weight {
	NSUserDefaults *uds = [NSUserDefaults standardUserDefaults];
	EWGoalState s = self.state;

	switch (s) {
		case EWGoalStateFixedRate:
			[self willChangeValueForKey:@"endDate"];
			break;
		case EWGoalStateFixedDate:
			[self willChangeValueForKey:@"weightChangePerDay"];
			break;
		default:
			[self willChangeValueForKey:@"endDate"];
			[self willChangeValueForKey:@"weightChangePerDay"];
			break;
	}
		
	@synchronized (self) {
		[self willChangeValueForKey:@"endWeight"];
		[uds setFloat:weight forKey:kGoalWeightKey];
		[self didChangeValueForKey:@"endWeight"];
	}
	
	switch (s) {
		case EWGoalStateFixedRate:
			[self didChangeValueForKey:@"endDate"];
			break;
		case EWGoalStateFixedDate:
			[self didChangeValueForKey:@"weightChangePerDay"];
			break;
		default:
			[uds setFloat:(((weight < self.currentWeight) ? -1 : 1) * kDefaultWeightChangePerDay) 
				   forKey:kGoalRateKey];
			[uds removeObjectForKey:kGoalDateKey];
			[self didChangeValueForKey:@"endDate"];
			[self didChangeValueForKey:@"weightChangePerDay"];
			break;
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:EWGoalDidChangeNotification object:self];
}


#pragma mark -


- (NSNumber *)endWeightNumber {
	float w = self.endWeight;
	if (w > 0) {
		return @(w);
	} else {
		return nil;
	}
}


- (void)setEndWeightNumber:(NSNumber *)number {
	self.endWeight = [number floatValue];
}


#pragma mark -


- (NSDate *)endDate {
	NSUserDefaults *uds = [NSUserDefaults standardUserDefaults];
	NSDate *date;
	@synchronized (self) {
		date = EWDateFromMonthDay((EWMonthDay)[uds integerForKey:kGoalDateKey]);
		if (date == nil) {
			// Don't use self.weightChangePerDay, to avoid potential infinite mutual recursion.
			float delta = [uds floatForKey:kGoalRateKey];
			float weightChange = self.endWeight - [self currentWeight];
			NSTimeInterval seconds = (weightChange / delta) * kSecondsPerDay;
			NSDate *todayDate = EWDateFromMonthDay(EWMonthDayToday());
			date = [todayDate dateByAddingTimeInterval:seconds];
		}
	}
	return date;
}


- (void)setEndDate:(NSDate *)date {
	NSUserDefaults *uds = [NSUserDefaults standardUserDefaults];
	EWMonthDay md = EWMonthDayFromDate(date);
	@synchronized (self) {
		[self willChangeValueForKey:@"endDate"];
		[self willChangeValueForKey:@"weightChangePerDay"];
		[uds setInteger:md forKey:kGoalDateKey];
		[uds removeObjectForKey:kGoalRateKey];
		[self didChangeValueForKey:@"endDate"];
		[self didChangeValueForKey:@"weightChangePerDay"];
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:EWGoalDidChangeNotification object:self];
}


#pragma mark -


- (float)weightChangePerDay {
	NSUserDefaults *uds = [NSUserDefaults standardUserDefaults];
	float delta;
	@synchronized (self) {
		NSNumber *number = [uds objectForKey:kGoalRateKey];
		if (number) {
			delta = [number floatValue];
		} else {
			// Don't use self.endDate, to avoid potential infinite mutual recursion.
			NSDate *goalDate = EWDateFromMonthDay((EWMonthDay)[uds integerForKey:kGoalDateKey]);
			NSDate *todayDate = EWDateFromMonthDay(EWMonthDayToday());
			NSTimeInterval seconds = [goalDate timeIntervalSinceDate:todayDate];
			float weightChange = self.endWeight - [self currentWeight];
			delta = weightChange / (float)(seconds / kSecondsPerDay);
		}
	}
	return delta;
}


- (void)setWeightChangePerDay:(float)delta {
	NSUserDefaults *uds = [NSUserDefaults standardUserDefaults];
	@synchronized (self) {
		[self willChangeValueForKey:@"endDate"];
		[self willChangeValueForKey:@"weightChangePerDay"];
		[uds setFloat:delta forKey:kGoalRateKey];
		[uds removeObjectForKey:kGoalDateKey];
		[self didChangeValueForKey:@"endDate"];
		[self didChangeValueForKey:@"weightChangePerDay"];
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:EWGoalDidChangeNotification object:self];
}


@end
