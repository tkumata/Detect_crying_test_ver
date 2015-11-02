//
//  ViewController.m
//  detect voice test1
//
//  Created by KUMATA Tomokatsu on 10/21/15.
//  Copyright © 2015 KUMATA Tomokatsu. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "MyFFT.h"

#define SAMPLE_RATE 44100.0f
#define REC_TIME 3.0f
#define LEVEL_PEAK -15.0f
#define s_FREQ @"300-600"
#define w_FREQ @"800-1000"
#define c_FREQ @"2000-4000"

// MARK: Decide threshold [dB]
// 30 ... silent
// 40 ... normal
// 50 ... loud
// 60+... too loud
#define CRY_THRESHOLD 50.0
#define NORMAL_THRESHOLD 40.0

@interface ViewController () <AVAudioPlayerDelegate, AVAudioRecorderDelegate> {
    AVAudioRecorder *avRecorder;
    
    NSMutableDictionary *_dictPlayers;
}

@end

// Save dir
#define DocumentsFolder [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]

@implementation ViewController

static void AudioInputCallback(
                               void* inUserData,
                               AudioQueueRef inAQ,
                               AudioQueueBufferRef inBuffer,
                               const AudioTimeStamp *inStartTime,
                               UInt32 inNumberPacketDescriptions,
                               const AudioStreamPacketDescription *inPacketDescs)
{
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    [self startUpdatingVolume];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark Sound Method

- (void)playSound:(NSString *)soundName loop:(NSInteger)loop {
    NSString *soundPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:soundName];
    NSURL *urlOfSound = [NSURL fileURLWithPath:soundPath];
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:urlOfSound error:nil];
    [player setNumberOfLoops:loop];
    player.delegate = (id)self;
    [player prepareToPlay];
    if (_dictPlayers == nil) _dictPlayers = [NSMutableDictionary dictionary];
    [_dictPlayers setObject:player forKey:[[player.url path] lastPathComponent]];
    player.volume = 0.7;
    [player play];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    [_dictPlayers removeObjectForKey:[[player.url path] lastPathComponent]];
}

#pragma mark Meter

- (void)startUpdatingVolume {
    // audio format
    AudioStreamBasicDescription dataFormat;
    dataFormat.mSampleRate = SAMPLE_RATE;
    dataFormat.mFormatID = kAudioFormatLinearPCM;
    dataFormat.mFormatFlags = kLinearPCMFormatFlagIsBigEndian | kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    dataFormat.mBytesPerPacket = 2;
    dataFormat.mFramesPerPacket = 1;
    dataFormat.mBytesPerFrame = 2;
    dataFormat.mChannelsPerFrame = 1;
    dataFormat.mBitsPerChannel = 16;
    dataFormat.mReserved = 0;
    
    // start queue
    AudioQueueNewInput(&dataFormat, AudioInputCallback, (__bridge void *)(self), CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &_queue);
    AudioQueueStart(_queue, NULL);
    
    // enable level meter
    UInt32 enabledLevelMeter = true;
    AudioQueueSetProperty(_queue, kAudioQueueProperty_EnableLevelMetering, &enabledLevelMeter, sizeof(UInt32));
    
    // timer for level meter
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                              target:self
                                            selector:@selector(detectVolume:)
                                            userInfo:nil
                                             repeats:YES];
}

- (void)stopUpdatingVolume {
    // Empty queue and stop Volume method
    AudioQueueFlush(_queue);
    AudioQueueStop(_queue, NO);
    AudioQueueDispose(_queue, YES);
}

// MARK: detect volume
- (void)detectVolume:(NSTimer *)timer {
    // Get mic level
    AudioQueueLevelMeterState levelMeter;
    UInt32 levelMeterSize = sizeof(AudioQueueLevelMeterState);
    AudioQueueGetProperty(_queue, kAudioQueueProperty_CurrentLevelMeterDB, &levelMeter, &levelMeterSize);
    
    // Display each level
    self.loudLabel.text = @"Hearing";
    self.peakTextField.text = [NSString stringWithFormat:@"%.2f", levelMeter.mPeakPower];
    self.averageTextField.text = [NSString stringWithFormat:@"%.2f", levelMeter.mAveragePower];
    
    // mPeakPower larger than -10.0 stop timer and start recording.
    if (levelMeter.mPeakPower >= LEVEL_PEAK) {
        // Stop timer
        [_timer invalidate];
        
        // Start recording
        [self record];
    }
}

#pragma mark Recording

- (void)record {
    // 録音データを保存する場所
    NSString *path = [NSString stringWithFormat:@"%@/audio.caf", DocumentsFolder];
    NSURL *url = [[NSURL alloc] initFileURLWithPath:path];
    
    // Recording settings parameter
    NSMutableDictionary *settings = [[NSMutableDictionary alloc] init];
    [settings setValue:[NSNumber numberWithInt:kAudioFormatLinearPCM] forKey:AVFormatIDKey];
    [settings setValue:[NSNumber numberWithFloat:SAMPLE_RATE] forKey:AVSampleRateKey];
    [settings setValue:[NSNumber numberWithInt:2] forKey:AVNumberOfChannelsKey];
    [settings setValue:[NSNumber numberWithInt:16] forKey:AVLinearPCMBitDepthKey];
    [settings setValue:[NSNumber numberWithBool:NO] forKey:AVLinearPCMIsBigEndianKey];
    [settings setValue:[NSNumber numberWithBool:NO] forKey:AVLinearPCMIsFloatKey];
    
    // create instance for recording
    NSError *error = nil;
    avRecorder = [[AVAudioRecorder alloc] initWithURL:url settings:settings error:&error];
    avRecorder.delegate = self;
    
    // 録音ファイルの準備(すでにファイルが存在していれば上書きしてくれる)
    [avRecorder prepareToRecord];
    
    // Start recording
    self.loudLabel.text = @"Recording";
    [avRecorder recordForDuration:REC_TIME];
}

- (void)viewDidDisappear:(BOOL)animated {
    // finish recording
    [avRecorder stop];
    [self stopUpdatingVolume];
    
    // remove recording data. DONOT call before stop method.
    //[avRecorder deleteRecording];
}

// 録音が終わったら呼ばれるメソッド
- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag {
#if DEBUG
    NSLog(@"%@", @"Finish recording.");
#endif
    
    [self process];
}

- (void)dealloc {
    avRecorder.delegate = nil;
}

#pragma mark FFT

- (void)process {
    self.loudLabel.text = @"";
    self.babyActLabel.text = @"";
    self.manActLabel.text = @"";
    self.otherActLabel.text = @"";
    
    NSString *soundPath = [NSString stringWithFormat:@"%@/audio.caf", DocumentsFolder];
    CFURLRef cfurl = (__bridge CFURLRef)[NSURL fileURLWithPath:soundPath];
    
    ExtAudioFileRef audioFile;
    OSStatus status;
    
    status = ExtAudioFileOpenURL(cfurl, &audioFile);
    
    const UInt32 frameCount = 4096;
    const int channelCountPerFrame = 1;
    
    AudioStreamBasicDescription clientFormat;
    clientFormat.mChannelsPerFrame = channelCountPerFrame;
    clientFormat.mSampleRate = SAMPLE_RATE;
    clientFormat.mFormatID = kAudioFormatLinearPCM;
    clientFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved;
    int cmpSize = sizeof(float);
    int frameSize = cmpSize*channelCountPerFrame;
    clientFormat.mBitsPerChannel = cmpSize*8;
    clientFormat.mBytesPerPacket = frameSize;
    clientFormat.mFramesPerPacket = 1;
    clientFormat.mBytesPerFrame = frameSize;
    
    status = ExtAudioFileSetProperty(audioFile, kExtAudioFileProperty_ClientDataFormat, sizeof(clientFormat), &clientFormat);
    
    // 後述するMyFFTクラスを使用
    MyFFT* fft = [[MyFFT alloc] initWithCapacity:frameCount];
    
    // magnitude vector array
    float vdist[frameCount];
    
    // magnitude scalar array for each frequency
    NSMutableArray *c_magniDic = [[NSMutableArray array] init];
    NSMutableArray *w_magniDic = [[NSMutableArray array] init];
    NSMutableArray *s_magniDic = [[NSMutableArray array] init];
    NSMutableArray *avgDic = [[NSMutableArray array] init];
    
    // bin width
    float bin = clientFormat.mSampleRate / frameCount;
    
    // max value of magnitude
    float max = 0.0;
    float prevmax = 0.0;

    // average of magnitude
    float avg = 0.0;
    
    while (true) {
        float buf[channelCountPerFrame*frameCount];
        AudioBuffer ab = { channelCountPerFrame, sizeof(buf), buf };
        AudioBufferList audioBufferList;
        audioBufferList.mNumberBuffers = 1;
        audioBufferList.mBuffers[0] = ab;
        
        UInt32 processedFrameCount = frameCount;
        status = ExtAudioFileRead(audioFile, &processedFrameCount, &audioBufferList);
        
        if (processedFrameCount == 0) {
            break;
        } else {
            // Calc FFT
            [fft process:buf];
            
            // Get magnitude in buffer
            vDSP_vdist([fft realp], 1, [fft imagp], 1, vdist, 1, frameCount);
            
            // Get max magnitude in buffer and add to array
            vDSP_maxv(vdist, 1, &max, frameCount);
            if (max > prevmax) {
                prevmax = max;
            }
            
            // Get avg magnitude in buffer and add to array
            vDSP_meanv(vdist, 1, &avg, frameCount);
            [avgDic addObject:[NSNumber numberWithFloat:avg]];
            
            // Separate some frequenct domain
            for (int i = 0; i < frameCount/2; i++) {
                float hz = i * bin;
                
                if (hz > (2000.0 - bin) && hz < (4000.0 + bin))
                {
                    [c_magniDic addObject:[NSNumber numberWithFloat:vdist[i]]];
                }
                else if (hz > 800.0 && hz < 1000.0)
                {
                    [w_magniDic addObject:[NSNumber numberWithFloat:vdist[i]]];
                }
                else if (hz > 300.0 && hz < 600.0)
                {
                    [s_magniDic addObject:[NSNumber numberWithFloat:vdist[i]]];
#if DEBUG
                    NSLog(@"%3d %8.2fHz %.2f", i, hz, vdist[i]);
#endif
                }
            }
        }
    }
    
    // MARK: Calc max magnitude [dB]
    float max_db = 20*log(prevmax);
    
    // MARK: Calc avg magnitude [dB]
    NSExpression *avgExpression = [NSExpression expressionForFunction:@"average:" arguments:@[[NSExpression expressionForConstantValue:avgDic]]];
    id avgValue = [avgExpression expressionValueWithObject:nil context:nil];
    float avg_db = 20*log([avgValue floatValue]);
    
    status = ExtAudioFileDispose(audioFile);
    
    // MARK: Calc each max value [dB]
    // calc max value for 300-600 Hz
    NSExpression *s_maxExpression = [NSExpression expressionForFunction:@"max:" arguments:@[[NSExpression expressionForConstantValue:s_magniDic]]];
    id s_maxValue = [s_maxExpression expressionValueWithObject:nil context:nil];
    float s_db = 20*log([s_maxValue floatValue]);
    
    if (s_db > NORMAL_THRESHOLD) {
        self.manActLabel.text = [NSString stringWithFormat:@"%@ Hz: %.2f dB", s_FREQ, s_db];
    } else {
        self.manActLabel.text = s_FREQ;
    }
    
    // calc max value for 800-1000 Hz
    NSExpression *w_maxExpression = [NSExpression expressionForFunction:@"max:" arguments:@[[NSExpression expressionForConstantValue:w_magniDic]]];
    id w_maxValue = [w_maxExpression expressionValueWithObject:nil context:nil];
    float w_db = 20*log([w_maxValue floatValue]);
    
    if (w_db > NORMAL_THRESHOLD) {
        self.otherActLabel.text = [NSString stringWithFormat:@"%@ Hz: %.2f dB", w_FREQ, w_db];
    } else {
        self.otherActLabel.text = w_FREQ;
    }
    
    // calc max value for crying (2000-4000 Hz)
    NSExpression *c_maxExpression = [NSExpression expressionForFunction:@"max:" arguments:@[[NSExpression expressionForConstantValue:c_magniDic]]];
    id c_maxValue = [c_maxExpression expressionValueWithObject:nil context:nil];
    float c_db = 20*log([c_maxValue floatValue]);
    
    if (c_db > CRY_THRESHOLD) {
        self.babyActLabel.text = [NSString stringWithFormat:@"%@ Hz: %.2f dB", c_FREQ, c_db];
    } else {
        self.babyActLabel.text = c_FREQ;
    }
    
    // MARK: Count high frequency
    int c_count = 0;
    for (id c_all_magni_each_bin in c_magniDic) {
        float c_all_db_each_bin = 20*log([c_all_magni_each_bin floatValue]);
        if (c_all_db_each_bin >= CRY_THRESHOLD) {
            c_count++;
        }
    }
    
    // Magnitude for Max value and AVG value
    self.maxLabel.text = [NSString stringWithFormat:@"max: %.2f dB / avg: %.2f dB", max_db, avg_db];
#if DEBUG
    NSLog(@"All c_magnitude: %lu / over max: %d", (unsigned long)[c_magniDic count], c_count);
    NSLog(@"max: %.2f dB / avg: %.2f dB", max_db, avg_db);
#endif
    
    // MARK: Maybe, baby is crying near.
    if (c_count >= 5) {
        [self performSelector:@selector(restartTimer:) withObject:nil afterDelay:30.0];
        
        // Play sound
        [self playSound:@"QPTarako.mp3" loop:0];
    } else {
        [self performSelector:@selector(restartTimer:) withObject:nil afterDelay:1.0];
    }
}

#pragma  mark Restart timer method

- (void)restartTimer:(int)t {
    // Timer again
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                              target:self
                                            selector:@selector(detectVolume:)
                                            userInfo:nil
                                             repeats:YES];
}

@end
