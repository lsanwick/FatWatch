//
//  WeightMonth.m
//  EatWatch
//
//  Created by Benjamin Ragheb on 4/6/08.
//  Copyright 2008 Benjamin Ragheb. All rights reserved.
//

#import "/usr/include/sqlite3.h"
#import "MonthData.h"
#import "Database.h"

#define SetBitValueAtIndex(b, v, i) if (v) { b |= (1 << (i)); } else { b &= ~(1 << (i)); }

static sqlite3_stmt *insert_stmt = nil;
static sqlite3_stmt *delete_stmt = nil;
static sqlite3_stmt *data_for_month_stmt = nil;

@implementation MonthData


@synthesize month;


+ (void)finalizeStatements {
	EWFinalizeStatement(&insert_stmt);
	EWFinalizeStatement(&delete_stmt);
	EWFinalizeStatement(&data_for_month_stmt);
}


- (id)initWithMonth:(EWMonth)m {
	if ([super init]) {
		month = m;
		
		scaleWeights = calloc(31, sizeof(float));
		trendWeights = calloc(31, sizeof(float));
		flagBits = 0;
		notesArray = [[NSMutableArray alloc] initWithCapacity:31];
		int i;
		for (i = 0; i < 31; i++) {
			[notesArray addObject:[NSNull null]];
		}
		dirtyBits = 0;
		
		if (data_for_month_stmt == nil) {
			data_for_month_stmt = [[Database sharedDatabase] statementFromSQL:"SELECT * FROM weight WHERE monthday > ? AND monthday < ?"];
		}
		sqlite3_bind_int(data_for_month_stmt, 1, EWMonthDayMake(m, 0));
		sqlite3_bind_int(data_for_month_stmt, 2, EWMonthDayMake(m+1, 0));
		while (sqlite3_step(data_for_month_stmt) == SQLITE_ROW) {
			EWDay day = EWMonthDayGetDay(sqlite3_column_int(data_for_month_stmt, kMonthDayColumnIndex));
			int i = day - 1;
			
			scaleWeights[i] = sqlite3_column_double(data_for_month_stmt, kScaleValueColumnIndex);
			trendWeights[i] = sqlite3_column_double(data_for_month_stmt, kTrendValueColumnIndex);
			SetBitValueAtIndex(flagBits, (sqlite3_column_int(data_for_month_stmt, kFlagColumnIndex) != 0), i);

			char *noteStr = (char *)sqlite3_column_text(data_for_month_stmt, kNoteColumnIndex);
			if (noteStr) {
				[notesArray replaceObjectAtIndex:i withObject:[NSString stringWithUTF8String:noteStr]];
			}
		}
		sqlite3_reset(data_for_month_stmt);
		
	}
	return self;
}


- (void)dealloc {
	free(scaleWeights);
	free(trendWeights);
	[notesArray release];
	[super dealloc];
}


- (NSString *)description {
	NSMutableString *text = [NSMutableString string];
	int i;
	
	[text appendFormat:@"month(%d) = {\n", month];
	for (i = 0; i < 31; i++) {
		if (scaleWeights[i] > 0) {
			[text appendFormat:@"\t%d: %f, %f\n", (i+1), scaleWeights[i], trendWeights[i]];
		}
	}
	[text appendFormat:@"}"];
	
	return text;
}


- (MonthData *)previousMonthData {
	Database *db = [Database sharedDatabase];
	if (self.month > db.earliestMonth) {
		return [db dataForMonth:(self.month - 1)];
	}
	return nil;
}


- (MonthData *)nextMonthData {
	Database *db = [Database sharedDatabase];
	if (self.month < db.latestMonth) {
		return [db dataForMonth:(self.month + 1)];
	}
	return nil;
}


- (NSDate *)dateOnDay:(EWDay)day {
	return EWDateFromMonthAndDay(month, day);
}


- (float)scaleWeightOnDay:(EWDay)day {
	return scaleWeights[day - 1];
}


- (float)trendWeightOnDay:(EWDay)day {
	return trendWeights[day - 1];
}


- (BOOL)isFlaggedOnDay:(EWDay)day {
	int i = day - 1;
	return (flagBits & (1 << i)) != 0;
}


- (NSString *)noteOnDay:(EWDay)day {
	id note = [notesArray objectAtIndex:(day - 1)];
	return (note == [NSNull null] ? nil : note);
}


- (EWDay)firstDayWithWeight {
	int i;
	
	for (i = 0; i < 31; i++) {
		if (scaleWeights[i] > 0) return (i + 1);
	}
	
	return 0;
}


- (EWDay)lastDayWithWeight {
	int i;
	
	for (i = 30; i >= 0; i--) {
		if (scaleWeights[i] > 0) return (i + 1);
	}
	
	return 0;
}


- (float)inputTrendOnDay:(EWDay)day {
	// Finds the trend value for the first day with data preceding the given day.
	// First, search backwards through this month for a trend value.
	int i;
	
	for (i = (day - 1) - 1; i >= 0; i--) {
		float trend = trendWeights[i];
		if (trend != 0) return trend;
	}
	
	// If none is found, find previous month with data.
	MonthData *previousMonthData = self.previousMonthData;
	if (previousMonthData) {
		float trend = [previousMonthData inputTrendOnDay:32];
		if (trend != 0) return trend;
	}

	// If day is 32, this is a recursive call, so return 0 to pop the stack.
	if (day == 32) return 0;

	// If nothing else, just give the weight on the specified day.
	return scaleWeights[day - 1];
}


- (float)lastTrendValueAfterUpdateStartingOnDay:(EWDay)day withInputTrend:(float)inputTrend {
	float previousTrend = inputTrend;
	int i;
	
	for (i = (day - 1); i < 31; i++) {
		if (scaleWeights[i] > 0) {
			trendWeights[i] = previousTrend + (0.1f * (scaleWeights[i] - previousTrend));
			SetBitValueAtIndex(dirtyBits, 1, i);
			previousTrend = trendWeights[i];
		}
	}
	
	return previousTrend;
}


- (void)setScaleWeight:(float)weight flag:(BOOL)flag note:(NSString *)note onDay:(EWDay)day {
	int i = day - 1;
	
	if (scaleWeights[i] != weight) {
		scaleWeights[i] = weight;
		trendWeights[i] = 0;
		[[Database sharedDatabase] didChangeWeightOnMonthDay:EWMonthDayMake(month, day)];
	}
	SetBitValueAtIndex(flagBits, flag, i);
	id object = (note != nil) ? (id)note : (id)[NSNull null];
	[notesArray replaceObjectAtIndex:i withObject:object];
	SetBitValueAtIndex(dirtyBits, 1, i);
}


- (BOOL)hasDataOnDay:(EWDay)day {
	return ([self scaleWeightOnDay:day] > 0 || 
			[self noteOnDay:day] != nil || 
			[self isFlaggedOnDay:day]);
}


- (BOOL)commitChanges {
	if (dirtyBits == 0) return NO;
	
	if (insert_stmt == nil) {
		insert_stmt = [[Database sharedDatabase] statementFromSQL:"INSERT OR REPLACE INTO weight VALUES(?,?,?,?,?)"];
	}
	
	if (delete_stmt == nil) {
		delete_stmt = [[Database sharedDatabase] statementFromSQL:"DELETE FROM weight WHERE monthday=?"];
	}
	
	int i = 0;
	unsigned int bits = dirtyBits;
	while (bits) {
		if (bits & 1 != 0) {
			EWDay day = i + 1;

			if ([self hasDataOnDay:day]) {
				// we have to add 1 to offsets because columns are 0-based and bindings are 1-based
				sqlite3_bind_int(insert_stmt, kMonthDayColumnIndex + 1, EWMonthDayMake(month, day));
				if (scaleWeights[i] == 0) {
					sqlite3_bind_null(insert_stmt, kScaleValueColumnIndex + 1);
					sqlite3_bind_null(insert_stmt, kTrendValueColumnIndex + 1);
				} else {
					sqlite3_bind_double(insert_stmt, kScaleValueColumnIndex + 1, scaleWeights[i]);
					sqlite3_bind_double(insert_stmt, kTrendValueColumnIndex + 1, trendWeights[i]);
				}
				sqlite3_bind_int(insert_stmt, kFlagColumnIndex + 1, [self isFlaggedOnDay:day]);
				id note = [notesArray objectAtIndex:i];
				if (note != [NSNull null]) {
					sqlite3_bind_text(insert_stmt, kNoteColumnIndex + 1, [note UTF8String], -1, SQLITE_STATIC);
				} else {
					sqlite3_bind_null(insert_stmt, kNoteColumnIndex + 1);
				}
				
				int retcode = sqlite3_step(insert_stmt);
				sqlite3_reset(insert_stmt);
				NSAssert1(retcode == SQLITE_DONE, @"INSERT returned code %d", retcode);
			} else {
				sqlite3_bind_int(delete_stmt, 1, EWMonthDayMake(month, day));
				int retcode = sqlite3_step(delete_stmt);
				sqlite3_reset(delete_stmt);
				NSAssert1(retcode == SQLITE_DONE, @"DELETE returned code %d", retcode);
			}
		}
		i++;
		bits >>= 1;
	}
	
	dirtyBits = 0;
	return YES;
}

@end
