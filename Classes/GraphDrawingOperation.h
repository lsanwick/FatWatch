//
//  GraphDrawingOperation.h
//  EatWatch
//
//  Created by Benjamin Ragheb on 9/4/08.
//  Copyright 2008 Benjamin Ragheb. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "EWDate.h"


typedef struct {
	float minWeight;
	float maxWeight;
	float scaleX;
	float scaleY;
	float gridMinWeight;
	float gridMaxWeight;
	float gridIncrementWeight;
	CGAffineTransform t;
	NSArray *regions;
	EWMonthDay mdEarliest;
	EWMonthDay mdLatest;
	BOOL shouldDrawNoDataWarning;
} GraphViewParameters;


typedef struct {
	CGPoint scale;
	CGPoint trend;
	BOOL flag;
} GraphPoint;


#define kDayWidth 8.0f


@interface GraphDrawingOperation : NSOperation {
	id delegate;
	int index;
	EWMonthDay beginMonthDay;
	EWMonthDay endMonthDay;
	GraphViewParameters *p;
	CGRect bounds;
	CGImageRef imageRef;
	NSMutableData *pointData;
	NSUInteger dayCount;
	CGPoint headPoint;
	CGPoint tailPoint;
}
+ (void)prepareGraphViewInfo:(GraphViewParameters *)gp forSize:(CGSize)size numberOfDays:(NSUInteger)numberOfDays;
@property (nonatomic) EWMonthDay beginMonthDay;
@property (nonatomic) EWMonthDay endMonthDay;
@property (nonatomic,assign) id delegate;
@property (nonatomic) int index;
@property (nonatomic) GraphViewParameters *p;
@property (nonatomic) CGRect bounds;
@property (nonatomic,readonly) CGImageRef imageRef;
+ (void)flushQueue;
- (void)enqueue;
@end


@interface NSObject (GraphDrawingOperationDelegate)
- (void)drawingOperationComplete:(GraphDrawingOperation *)operation;
@end
