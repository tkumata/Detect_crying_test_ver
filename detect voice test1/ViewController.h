//
//  ViewController.h
//  detect voice test1
//
//  Created by KUMATA Tomokatsu on 10/21/15.
//  Copyright © 2015 KUMATA Tomokatsu. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>

@interface ViewController : UIViewController
{
    AudioQueueRef   _queue;     // 音声入力用のキュー
    NSTimer         *_timer;    // 監視タイマー
}

@property (weak, nonatomic) IBOutlet UILabel *loudLabel;

@property (weak, nonatomic) IBOutlet UILabel *babyActLabel;
@property (weak, nonatomic) IBOutlet UILabel *manActLabel;
@property (weak, nonatomic) IBOutlet UILabel *otherActLabel;

@property (weak, nonatomic) IBOutlet UILabel *maxLabel;

@property (weak, nonatomic) IBOutlet UITextField *peakTextField;
@property (weak, nonatomic) IBOutlet UITextField *averageTextField;

@end

