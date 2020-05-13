#import "RNSoundManager.h"
#import <React/RCTConvert.h>
#import <React/RCTNetworking.h>
#import <AVFoundation/AVFoundation.h>

@implementation RNSoundManager
{
  NSSound *_player;
}

RCT_EXPORT_MODULE()

@synthesize bridge = _bridge;

- (instancetype)init
{
  if (self = [super init]) {
    _player = nil;
  }
  return self;
}

- (dispatch_queue_t)methodQueue
{
  dispatch_queue_attr_t attr =
    dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);

  return dispatch_queue_create("oss.react-native.RNSound", attr);
}

NSString *RCTFailedToLoad(NSURL *url, NSString *message) {
  return [NSString stringWithFormat:@"[RNSound] Failed to load \"%@\": %@", url.absoluteString, message];
}

RCT_REMAP_METHOD(preload,
                 source:(id)source
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  NSURLRequest *request = [RCTConvert NSURLRequest:source];
  if (!request) {
    return reject(RCTErrorUnspecified, @"[RNSound] Expected \"source\" prop to be a URL request", nil);
  }

  RCTNetworkTask *task = [_bridge.networking
    networkTaskWithRequest:request
    completionBlock:^(__unused NSURLResponse *response, NSData *data, NSError *error) {
      if (error) {
        return reject(RCTErrorUnspecified, RCTFailedToLoad(request.URL, error.localizedDescription), error);
      }
        
      if (self->_player) {
        [self->_player stop];
      }
        
      self->_player = [[NSSound alloc] initWithContentsOfURL:[NSURL URLWithString:source] byReference:NO];

      resolve(nil);
    }];
  [task start];
}


RCT_REMAP_METHOD(stop,
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    if (!self->_player) {
        return reject(RCTErrorUnspecified, @"Source not yet loaded", nil);
    }
    [self->_player stop];
    resolve(nil);
}

RCT_REMAP_METHOD(pause,
                 pause_resolver:(RCTPromiseResolveBlock)resolve
                 pause_rejecter:(RCTPromiseRejectBlock)reject)
{
    if (!self->_player) {
        return reject(RCTErrorUnspecified, @"Source not yet loaded", nil);
    }
    [self->_player pause];
    resolve(nil);
}

RCT_REMAP_METHOD(resume,
                 resume_resolver:(RCTPromiseResolveBlock)resolve
                 resume_rejecter:(RCTPromiseRejectBlock)reject)
{
    if (!self->_player) {
        return reject(RCTErrorUnspecified, @"Source not yet loaded", nil);
    }
    [self->_player resume];
    resolve(nil);
}

RCT_REMAP_METHOD(setVolume,
                 volume:(float)volume
                 setVolume_resolver:(RCTPromiseResolveBlock)resolve
                 setVolume_rejecter:(RCTPromiseRejectBlock)reject)
{
    if (!self->_player) {
        return reject(RCTErrorUnspecified, @"Source not yet loaded", nil);
    }
    self->_player.volume = volume;
    resolve(nil);
}

RCT_REMAP_METHOD(play,
                 options:(NSDictionary *)options
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
  if (!self->_player) {
    return reject(RCTErrorUnspecified, @"Source not yet loaded", nil);
  }
    
    if(!self->_player.isPlaying) {
        self->_player.volume = options[@"volume"]
        ? [RCTConvert float:options[@"volume"]]
        : 1.0;
        self->_player.loops = options[@"loops"] ? [RCTConvert BOOL:options[@"loops"]]
        : false;
        
        [self->_player play];
    }
  resolve(nil);
}

@end
