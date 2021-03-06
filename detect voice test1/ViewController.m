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
#define REC_TIME 1.6f
#define LEVEL_PEAK -16.0f
#define NORMAL_FREQ @"301-700" // freq range which human speaks.
#define W_FREQ @"801-1000" // i forgot. X(
#define CRYING_FREQ @"2001-5000" // freq range when baby cry.

// MARK: Decide threshold [dB]
#define CRY_THRESHOLD 50.0f
#define NORMAL_THRESHOLD 50.0f

// q value threshold
#define Q_THRESHOLD 5.5f

// Timer interval
#define INTERVAL 0.5f

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
    
    if (_dictPlayers == nil) {
        _dictPlayers = [NSMutableDictionary dictionary];
    }
    
    [_dictPlayers setObject:player forKey:[[player.url path] lastPathComponent]];
    [player setVolume: 1.0];
    player.volume = 1.0f;
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
    _timer = [NSTimer scheduledTimerWithTimeInterval:INTERVAL
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
    
    // stop timer and start recording.
    if (levelMeter.mPeakPower >= LEVEL_PEAK) {
        // Stop timer
        [_timer invalidate];
        
        // Start recording
#ifdef DEBUG
        NSLog(@"Start recording.");
#endif
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
    [avRecorder deleteRecording];
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
    NSMutableArray *crying_magnitude_dict = [[NSMutableArray array] init];
    NSMutableArray *w_magnitude_dict = [[NSMutableArray array] init];
    NSMutableArray *normal_magnitude_dict = [[NSMutableArray array] init];
    NSMutableArray *avgDic = [[NSMutableArray array] init];
    NSMutableArray *q3k_avgDic = [[NSMutableArray array] init];
    NSMutableArray *q6k_avgDic = [[NSMutableArray array] init];
    
    // bin width
    float bin = clientFormat.mSampleRate / frameCount;
    
    // max value of magnitude
    float max = 0.0;
    float max_db_per_buff = 0.0;

    // average of magnitude
    float avg = 0.0;
    
    float q3k = 0.0;
    float q6k = 0.0;
    
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
            if (max > max_db_per_buff) {
                max_db_per_buff = max;
            }
            
            // Get avg magnitude in buffer and add to array
            vDSP_meanv(vdist, 1, &avg, frameCount);
            [avgDic addObject:[NSNumber numberWithFloat:avg]];
            
            // Separate some frequenct domain
            for (int i = 0; i < frameCount/2; i++) {
                float hz = i * bin;
                
                // MARK: Gather magnitude for 'q' seed
                if (hz > 2000.f && hz < 5000.f) {
                    [q3k_avgDic addObject:[NSNumber numberWithFloat:vdist[i]]];
                } else if (hz > 5000.f && hz < 8000.f) {
                    [q6k_avgDic addObject:[NSNumber numberWithFloat:vdist[i]]];
                }
                
                // MARK: Gather magnitude each frequency
                if (hz > 2000.f && hz < 8000.f) {
                    [crying_magnitude_dict addObject:[NSNumber numberWithFloat:vdist[i]]];
                } else if (hz > 800.f && hz < 1000.f) {
                    [w_magnitude_dict addObject:[NSNumber numberWithFloat:vdist[i]]];
                } else if (hz > 300.f && hz < 700.f) {
                    [normal_magnitude_dict addObject:[NSNumber numberWithFloat:vdist[i]]];
                }
            }
        }
    }
    
    status = ExtAudioFileDispose(audioFile);
    
    // MARK: Calc max total magnitude [dB]
    float max_db = 20*log(max_db_per_buff);
    
    // MARK: Calc avg total magnitude [dB]
    NSExpression *avgExpression = [NSExpression expressionForFunction:@"average:"
                                                            arguments:@[[NSExpression expressionForConstantValue:avgDic]]];
    id avgValue = [avgExpression expressionValueWithObject:nil context:nil];
    float avg_db = 20*log([avgValue floatValue]);
    
    // MARK: Calc avg 'q'
    // 1st 3kHz
    NSExpression *q3k_avgExpression = [NSExpression expressionForFunction:@"sum:"
                                                                arguments:@[[NSExpression expressionForConstantValue:q3k_avgDic]]];
    id q3k_avgValue = [q3k_avgExpression expressionValueWithObject:nil context:nil];
    q3k = fabsf([q3k_avgValue floatValue]);
    
    // 2nd 6kHz
    NSExpression *q6k_avgExpression = [NSExpression expressionForFunction:@"sum:"
                                                                arguments:@[[NSExpression expressionForConstantValue:q6k_avgDic]]];
    id q6k_avgValue = [q6k_avgExpression expressionValueWithObject:nil context:nil];
    q6k = fabsf([q6k_avgValue floatValue]);

    // MARK: ave[F(i)/F(i+1)]
    float q3k6k = q3k/q6k;
    
    // MARK: Calc each max value [dB]
    // calc max value for 300-600 Hz
    NSExpression *normal_maxExpression = [NSExpression expressionForFunction:@"max:"
                                                                   arguments:@[[NSExpression expressionForConstantValue:normal_magnitude_dict]]];
    id normal_max_value = [normal_maxExpression expressionValueWithObject:nil context:nil];
    float normal_db = 20*log([normal_max_value floatValue]);
    
    if (normal_db > NORMAL_THRESHOLD) {
#ifdef DEBUG
        NSLog(@"%@ Hz: %.2f dB", NORMAL_FREQ, normal_db);
#endif
        self.manActLabel.text = [NSString stringWithFormat:@"%@ Hz: %.2f dB", NORMAL_FREQ, normal_db];
    } else {
        self.manActLabel.text = [NSString stringWithFormat:@"%@ Hz:", NORMAL_FREQ];
    }
    
    // calc max value for 800-1000 Hz
    NSExpression *w_maxExpression = [NSExpression expressionForFunction:@"max:"
                                                              arguments:@[[NSExpression expressionForConstantValue:w_magnitude_dict]]];
    id w_maxValue = [w_maxExpression expressionValueWithObject:nil context:nil];
    float w_db = 20*log([w_maxValue floatValue]);
    
    if (w_db > NORMAL_THRESHOLD) {
#ifdef DEBUG
        NSLog(@"%@ Hz: %.2f dB", W_FREQ, w_db);
#endif
        self.otherActLabel.text = [NSString stringWithFormat:@"%@ Hz: %.2f dB", W_FREQ, w_db];
    } else {
        self.otherActLabel.text = [NSString stringWithFormat:@"%@ Hz:", W_FREQ];
    }
    
    // calc max value for crying (2000-4000 Hz)
    NSExpression *crying_maxExpression = [NSExpression expressionForFunction:@"max:"
                                                                   arguments:@[[NSExpression expressionForConstantValue:crying_magnitude_dict]]];
    id crying_max_value = [crying_maxExpression expressionValueWithObject:nil context:nil];
    float crying_db = 20*log([crying_max_value floatValue]);
    
    if (crying_db > CRY_THRESHOLD) {
#ifdef DEBUG
        NSLog(@"%@ Hz: %.2f dB", CRYING_FREQ, crying_db);
#endif
        self.babyActLabel.text = [NSString stringWithFormat:@"%@ Hz: %.2f dB", CRYING_FREQ, crying_db];
    } else {
        self.babyActLabel.text = [NSString stringWithFormat:@"%@ Hz:", CRYING_FREQ];
    }
    
    // Magnitude for Max value and AVG value
    self.maxLabel.text = [NSString stringWithFormat:@"max: %.2f dB / avg: %.2f dB\nq: %.2f", max_db, avg_db, q3k6k];
    
#ifdef DEBUG
    NSLog(@"max: %.2f dB / avg: %.2f dB", max_db, avg_db);
    NSLog(@"q: %.2f", q3k6k);
#endif
    
    // MARK: Maybe, baby is crying near.
    if (q3k6k >= Q_THRESHOLD) {
        [self performSelector:@selector(restartTimer:) withObject:nil afterDelay:30.0];
        
        self.loudLabel.text = @"Crying";
        self.view.backgroundColor = [UIColor yellowColor];

        // Play sound
        [self playSound:@"QPTarako.mp3" loop:0];
    } else {
        [self performSelector:@selector(restartTimer:) withObject:nil afterDelay:INTERVAL];
    }
}

#pragma  mark Restart timer method

- (void)restartTimer:(int)t {
    self.view.backgroundColor = [UIColor whiteColor];
    
    // Timer again
    _timer = [NSTimer scheduledTimerWithTimeInterval:INTERVAL
                                              target:self
                                            selector:@selector(detectVolume:)
                                            userInfo:nil
                                             repeats:YES];
}

@end
