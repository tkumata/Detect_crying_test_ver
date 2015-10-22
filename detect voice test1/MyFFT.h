//
//  MyFFT.h
//  detect voice test1
//
//  Created by KUMATA Tomokatsu on 10/22/15.
//  Copyright © 2015 KUMATA Tomokatsu. All rights reserved.
//

//#ifndef MyFFT_h
//#define MyFFT_h

//
//  MyFFT(revision 1)
//  MyFFT.h
//  http://nantekottai.com/
//

#import <UIKit/UIKit.h>
//#import <Foundation/Foundation.h>
#import <Accelerate/Accelerate.h>

@interface MyFFT : NSObject {
    DSPSplitComplex splitComplex;
    FFTSetup fftSetup;
    unsigned int capacity;
    unsigned int capacityN;	//capacityが2の何乗であるかを保持
    float* window;
    float* windowedInput;
}
@property (assign) unsigned int capacity;
@property (readonly) float* realp;
@property (readonly) float* imagp;
- (void)process:(float*)input;
- (id)initWithCapacity:(unsigned int)aCapacity;
@end

//#endif /* MyFFT_h */
