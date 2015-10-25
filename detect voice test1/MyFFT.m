//
//  MyFFT.m
//  detect voice test1
//
//  Created by KUMATA Tomokatsu on 10/22/15.
//  Copyright © 2015 KUMATA Tomokatsu. All rights reserved.
//
//
//  MyFFT.m
//  http://nantekottai.com/
//

#import "MyFFT.h"

@implementation MyFFT
@synthesize capacity;

- (float *)realp
{
    return splitComplex.realp;
}

- (float *)imagp
{
    return splitComplex.imagp;
}

- (id)initWithCapacity:(unsigned int)aCapacity
{
    if (self = [super init]) {
        
        // aCapacityが2のn乗になっているか調べます
        // aCapacityが2のn乗になっていない場合は、
        // 2のn乗になるように調整します。
        // (厳密にやりたい場合は0のチェック等も行ってください)
        capacityN = log(aCapacity) / log(2);
        capacity = 1 << capacityN;
        
        NSLog(@"capacity: %d n: %d", capacity, capacityN);
        
        // FFTの設定をします
        fftSetup = vDSP_create_fftsetup(capacityN + 1, FFT_RADIX2);
        
        // FFTに使う配列を用意します
        splitComplex.realp = calloc(capacity, sizeof(float));
        splitComplex.imagp = calloc(capacity, sizeof(float));
        
        // 窓用の配列を用意します
        window = calloc(capacity, sizeof(float));
        windowedInput = calloc(capacity, sizeof(float));
        
        // 窓を作ります
        vDSP_hann_window(window, capacity, 0);
    }
    return self;
}

- (void)process:(float*)input
{
    // 窓をかけます
    vDSP_vmul(input, 1, window, 1, windowedInput, 1, capacity);
    
    // 複素数に変換します
    for (int i=0; i < capacity; i++) {
        splitComplex.realp[i] = windowedInput[i];
        splitComplex.imagp[i] = 0.0f;
    }
    
    // フーリエ変換します
    vDSP_fft_zrip(fftSetup, &splitComplex, 1, capacityN + 1, FFT_FORWARD);
//    vDSP_fft_zrip(fftSetup, &splitComplex, 1, capacityN, FFT_FORWARD);
    
//    for (int i = 0; i <= capacity/2; i++) {
//        float real = splitComplex.realp[i];
//        float imag = splitComplex.imagp[i];
//        float distance = sqrt(real*real + imag*imag);
//        NSLog(@"[%d] %.2f", i, distance);
//    }
}

- (void)dealloc
{
    // FFTに使う配列を解放します
    free(splitComplex.realp);
    free(splitComplex.imagp);
    
    // 窓用の配列を解放します
    free(window);
    free(windowedInput);
    
    // FFTの設定を削除します
    vDSP_destroy_fftsetup(fftSetup);
}

@end