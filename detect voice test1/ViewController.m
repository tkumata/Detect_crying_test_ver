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
    // 録音はしないので未実装
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
    player.volume = 1.0;
    [player play];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    [_dictPlayers removeObjectForKey:[[player.url path] lastPathComponent]];
}

#pragma mark Meter

- (void)startUpdatingVolume {
    // 記録するデータフォーマットを決める
    AudioStreamBasicDescription dataFormat;
    dataFormat.mSampleRate = 44100.0f;
    dataFormat.mFormatID = kAudioFormatLinearPCM;
    dataFormat.mFormatFlags = kLinearPCMFormatFlagIsBigEndian | kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    dataFormat.mBytesPerPacket = 2;
    dataFormat.mFramesPerPacket = 1;
    dataFormat.mBytesPerFrame = 2;
    dataFormat.mChannelsPerFrame = 1;
    dataFormat.mBitsPerChannel = 16;
    dataFormat.mReserved = 0;
    
    // レベルの監視を開始する
    AudioQueueNewInput(&dataFormat, AudioInputCallback, (__bridge void *)(self), CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &_queue);
    AudioQueueStart(_queue, NULL);
    
    // レベルメータを有効化する
    UInt32 enabledLevelMeter = true;
    AudioQueueSetProperty(_queue, kAudioQueueProperty_EnableLevelMetering, &enabledLevelMeter, sizeof(UInt32));
    
    // 定期的にレベルメータを監視する
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
    if (levelMeter.mPeakPower >= -10.0f) {
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
    [settings setValue:[NSNumber numberWithFloat:44100.0f] forKey:AVSampleRateKey];
    [settings setValue:[NSNumber numberWithInt:2] forKey:AVNumberOfChannelsKey];
    [settings setValue:[NSNumber numberWithInt:16] forKey:AVLinearPCMBitDepthKey];
    [settings setValue:[NSNumber numberWithBool:NO] forKey:AVLinearPCMIsBigEndianKey];
    [settings setValue:[NSNumber numberWithBool:NO] forKey:AVLinearPCMIsFloatKey];
    
    // インスタンス生成(エラー処理は省略)
    NSError *error = nil;
    avRecorder = [[AVAudioRecorder alloc] initWithURL:url settings:settings error:&error];
    avRecorder.delegate = self;
    
    // 録音ファイルの準備(すでにファイルが存在していれば上書きしてくれる)
    [avRecorder prepareToRecord];
    
    // 録音中に音量をとるかどうか
    avRecorder.meteringEnabled = YES;
    
    // Start recording
    self.loudLabel.text = @"Recording";
    [avRecorder recordForDuration:4.0];
}

- (void)viewDidDisappear:(BOOL)animated {
    // 録音終了
    [avRecorder stop];
    [self stopUpdatingVolume];
    
    // 録音データの削除。stop メソッドを呼ぶ前に呼んではいけない
//    [avRecorder deleteRecording];
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
    
    const UInt32 frameCount = 1024;
    const int channelCountPerFrame = 1;
    
    AudioStreamBasicDescription clientFormat;
    clientFormat.mChannelsPerFrame = channelCountPerFrame;
    clientFormat.mSampleRate = 44100.0f;
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
                
                if (hz > 2000 && hz < 4000)
                {
                    [c_magniDic addObject:[NSNumber numberWithFloat:vdist[i]]];
                }
                else if (hz > 800 && hz < 1000)
                {
                    [w_magniDic addObject:[NSNumber numberWithFloat:vdist[i]]];
                }
                else if (hz > 300 && hz < 600)
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
    
    // MARK: Decide threshold [dB]
    // 30 ... silent
    // 40 ... normal
    // 50 ... loud
    // 60+... too loud
    float threshold_db_s = 40.0;
    float threshold_db_w = 40.0;
    float threshold_db_c = 50.0;
    
    status = ExtAudioFileDispose(audioFile);
    
    // MARK: Calc each max value [dB]
    // calc max value
    NSExpression *s_maxExpression = [NSExpression expressionForFunction:@"max:" arguments:@[[NSExpression expressionForConstantValue:s_magniDic]]];
    id s_maxValue = [s_maxExpression expressionValueWithObject:nil context:nil];
    float s_db = 20*log([s_maxValue floatValue]);
    
    if (s_db > threshold_db_s) {
        self.manActLabel.text = [NSString stringWithFormat:@"300-600 Hz: %.2f dB", s_db];
    } else {
        self.manActLabel.text = @"---";
    }
    
    // calc max value
    NSExpression *w_maxExpression = [NSExpression expressionForFunction:@"max:" arguments:@[[NSExpression expressionForConstantValue:w_magniDic]]];
    id w_maxValue = [w_maxExpression expressionValueWithObject:nil context:nil];
    float w_db = 20*log([w_maxValue floatValue]);
    
    if (w_db > threshold_db_w) {
        self.otherActLabel.text = [NSString stringWithFormat:@"800-1000 Hz: %.2f dB", w_db];
    } else {
        self.otherActLabel.text = @"---";
    }
    
    // calc max value for crying
    NSExpression *c_maxExpression = [NSExpression expressionForFunction:@"max:" arguments:@[[NSExpression expressionForConstantValue:c_magniDic]]];
    id c_maxValue = [c_maxExpression expressionValueWithObject:nil context:nil];
    float c_db = 20*log([c_maxValue floatValue]);
    
    if (c_db > threshold_db_c) {
        self.babyActLabel.text = [NSString stringWithFormat:@"2000-4000 Hz: %.2f dB", c_db];
    } else {
        self.babyActLabel.text = @"---";
    }
    
    // MARK: Count times for near max value
    int c_Loop = 0;
    for (id c_all_magni in c_magniDic) {
        float c_all_dB = 20*log([c_all_magni floatValue]);
        if (c_all_dB >= max_db - 5) {
            c_Loop++;
        }
    }
    
    // Magnitude for Max value and AVG value
    self.maxLabel.text = [NSString stringWithFormat:@"max: %.2f dB / avg: %.2f dB", max_db, avg_db];
    
#if DEBUG
    NSLog(@"All c_magnitude: %lu / over max: %d", (unsigned long)[c_magniDic count], c_Loop);
    NSLog(@"max: %.2f dB / avg: %.2f dB", max_db, avg_db);
#endif
    
    // MARK: Maybe, baby is crying near.
    if (c_db == max_db && c_Loop >= 7) {
        [self performSelector:@selector(restartTimer:) withObject:nil afterDelay:63.0];
        
        // Play sound
        [self playSound:@"Water.mp3" loop:3];
    } else {
        [self performSelector:@selector(restartTimer:) withObject:nil afterDelay:5.0];
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
