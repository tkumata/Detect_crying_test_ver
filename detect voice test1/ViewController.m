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
    AVAudioPlayer *avPlayer;
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
    // キューを空にして停止
    AudioQueueFlush(_queue);
    AudioQueueStop(_queue, NO);
    AudioQueueDispose(_queue, YES);
}

- (void)detectVolume:(NSTimer *)timer {
    // レベルを取得
    AudioQueueLevelMeterState levelMeter;
    UInt32 levelMeterSize = sizeof(AudioQueueLevelMeterState);
    AudioQueueGetProperty(_queue, kAudioQueueProperty_CurrentLevelMeterDB, &levelMeter, &levelMeterSize);
    
    // 最大レベル、平均レベルを表示
    self.loudLabel.text = @"Hearing";
    self.peakTextField.text = [NSString stringWithFormat:@"%.2f", levelMeter.mPeakPower];
    self.averageTextField.text = [NSString stringWithFormat:@"%.2f", levelMeter.mAveragePower];
    
    // mPeakPowerが -1.0 以上なら "LOUD!!" と表示
//    self.loudLabel.hidden = (levelMeter.mPeakPower >= -1.0f) ? NO : YES;
    if (levelMeter.mPeakPower >= -10.0f) {
        [_timer invalidate];
        
        [self record];
    }
}

#pragma mark Recording

- (void)record {
    // 録音データを保存する場所
    NSString *path = [NSString stringWithFormat:@"%@/audio.caf", DocumentsFolder];
    NSURL *url = [[NSURL alloc] initFileURLWithPath:path];
    
//    NSMutableDictionary *settings = [[NSMutableDictionary alloc] init];
//    [settings setValue:[NSNumber numberWithInt:kAudioFormatLinearPCM] forKey:AVFormatIDKey];
//    [settings setValue:[NSNumber numberWithFloat:44100.0f] forKey:AVSampleRateKey];
//    [settings setValue:[NSNumber numberWithInt:1] forKey:AVNumberOfChannelsKey];
//    [settings setValue:[NSNumber numberWithInt:16] forKey:AVLinearPCMBitDepthKey];
//    [settings setValue:[NSNumber numberWithBool:NO] forKey:AVLinearPCMIsBigEndianKey];
//    [settings setValue:[NSNumber numberWithBool:NO] forKey:AVLinearPCMIsFloatKey];
    
    // 録音の設定 AVNumberOfChannelsKey チャンネル数1
    NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithFloat:44100.0f], AVSampleRateKey,
                              [NSNumber numberWithInt:kAudioFormatLinearPCM], AVFormatIDKey,
                              [NSNumber numberWithInt:1], AVNumberOfChannelsKey,
                              [NSNumber numberWithInt:16], AVLinearPCMBitDepthKey,
                              [NSNumber numberWithBool:NO], AVLinearPCMIsBigEndianKey,
                              [NSNumber numberWithBool:NO], AVLinearPCMIsFloatKey,
                              nil];
    
    // インスタンス生成(エラー処理は省略)
    NSError *error = nil;
    avRecorder = [[AVAudioRecorder alloc] initWithURL:url settings:settings error:&error];
    avRecorder.delegate = self;
    
    // 録音ファイルの準備(すでにファイルが存在していれば上書きしてくれる)
    [avRecorder prepareToRecord];
    
    // 録音中に音量をとるかどうか
    avRecorder.meteringEnabled = YES;
    
    // 録音開始
//    [recorder record];
    self.loudLabel.text = @"Recording";
    [avRecorder recordForDuration:4.0];
}

- (void)viewDidDisappear:(BOOL)animated {
    // 録音終了
    [avRecorder stop];
    [self stopUpdatingVolume];
    
    // 録音データの削除。stop メソッドを呼ぶ前に呼んではいけない
    [avRecorder deleteRecording];
}

// 録音が終わったら呼ばれるメソッド
- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag {
    NSLog(@"%@", @"Finish recording.");
    [self process];
//    [self play];
}

- (void)dealloc {
    avRecorder.delegate = nil;
}

#pragma Play recorded file

- (void)play {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryAmbient error:nil];
    
    // 録音ファイルパス
//    NSArray *filePaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
//    NSString *documentDir = [filePaths objectAtIndex:0];
//    NSString *path = [documentDir stringByAppendingPathComponent:@"audio.caf"];
    NSString *path = [NSString stringWithFormat:@"%@/audio.caf", DocumentsFolder];
    NSURL *recordingURL = [NSURL fileURLWithPath:path];
    
    //再生
    avPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:recordingURL error:nil];
    avPlayer.delegate = self;
    avPlayer.volume = 1.0;
    [avPlayer play];
//    [self processFFT];
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
    clientFormat.mSampleRate = 44100.f;
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
            [fft process:buf];
        }
    }
    
    // magnitude
    float vdist[frameCount];
    vDSP_vdist([fft realp], 1, [fft imagp], 1, vdist, 1, frameCount);
    
    // max value of magnitude
    float max;
    vDSP_maxv(vdist, 1, &max, frameCount);
    float max_db = 20*log(max);
    
    // average of magnitude
    float avg;
    vDSP_meanv(vdist, 1, &avg, frameCount);
    float avg_db = 20*log(avg);
    
    float bin = clientFormat.mSampleRate / frameCount;
//    float threshold = max*4/10;
    float threshold_db = 40.0; // 30...silent, 40...normal, 50...loud, 60+...too loud
    
    NSMutableArray *c_magniDic = [[NSMutableArray array] init];
    NSMutableArray *w_magniDic = [[NSMutableArray array] init];
    NSMutableArray *s_magniDic = [[NSMutableArray array] init];
    
    for (int i = 0; i < frameCount/2; i++) {
        float hz = i * bin;
        
//        NSLog(@"%3d %8.2fHz %.2f", i, hz, vdist[i]);
        
        if (hz > 2000 && hz < 4000)
        {
            [c_magniDic addObject:[NSNumber numberWithFloat:vdist[i]]];
        }
        else if (hz > 800 && hz < 1000)
        {
            [w_magniDic addObject:[NSNumber numberWithFloat:vdist[i]]];
        }
        else if (hz > 400 && hz < 800)
        {
            [s_magniDic addObject:[NSNumber numberWithFloat:vdist[i]]];
        }
    }
    
    status = ExtAudioFileDispose(audioFile);
    
    // calc max value
    NSExpression *s_maxExpression = [NSExpression expressionForFunction:@"max:" arguments:@[[NSExpression expressionForConstantValue:s_magniDic]]];
    id s_maxValue = [s_maxExpression expressionValueWithObject:nil context:nil];
    float s_db = 20*log([s_maxValue floatValue]);
    
    if (s_db > threshold_db) {
        self.manActLabel.text = [NSString stringWithFormat:@"400-800 Hz: %.2f dB", s_db];
    } else {
        self.manActLabel.text = @"---";
    }
    
    // calc max value
    NSExpression *w_maxExpression = [NSExpression expressionForFunction:@"max:" arguments:@[[NSExpression expressionForConstantValue:w_magniDic]]];
    id w_maxValue = [w_maxExpression expressionValueWithObject:nil context:nil];
    float w_db = 20*log([w_maxValue floatValue]);
    
    if (w_db > threshold_db) {
        self.otherActLabel.text = [NSString stringWithFormat:@"800-1000 Hz: %.2f dB", w_db];
    } else {
        self.otherActLabel.text = @"---";
    }
    
    // calc max value
    NSExpression *c_maxExpression = [NSExpression expressionForFunction:@"max:" arguments:@[[NSExpression expressionForConstantValue:c_magniDic]]];
    id c_maxValue = [c_maxExpression expressionValueWithObject:nil context:nil];
    float c_db = 20*log([c_maxValue floatValue]);
    
    if (c_db > threshold_db) {
        self.babyActLabel.text = [NSString stringWithFormat:@"2000-4000 Hz: %.2f dB", c_db];
    } else {
        self.babyActLabel.text = @"---";
    }
    
//    NSLog(@"max: M%.2f avg: M%.2f", max, avg);
    self.maxLabel.text = [NSString stringWithFormat:@"max: %.2f dB / avg: %.2f dB", max_db, avg_db];
    
    // if c_maxValue == max, baby cry near.
    if (c_db == max_db) {
        [self performSelector:@selector(restartTimer:) withObject:nil afterDelay:180.0];
    } else {
        [self performSelector:@selector(restartTimer:) withObject:nil afterDelay:10.0];
    }
}

- (void)restartTimer:(int)t {
    // Timer again
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                              target:self
                                            selector:@selector(detectVolume:)
                                            userInfo:nil
                                             repeats:YES];
}

@end
