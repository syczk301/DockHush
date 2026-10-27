// External Qt 6.7 bootstrap plugin. The optional theme factory returns no theme,
// so Qt retains its native Cocoa theme. No vendor bundle file is modified.
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <unistd.h>
static const unsigned char qt_metadata[] __attribute__((used,section("__TEXT,qtmetadata"))) = {81,84,77,69,84,65,68,65,84,65,32,33,1,6,7,0,191,2,120,56,111,114,103,46,113,116,45,112,114,111,106,101,99,116,46,81,116,46,81,80,65,46,81,80,108,97,116,102,111,114,109,84,104,101,109,101,70,97,99,116,111,114,121,73,110,116,101,114,102,97,99,101,46,53,46,49,3,115,68,111,99,107,72,117,115,104,84,101,109,112,111,80,108,117,103,105,110,4,161,100,75,101,121,115,129,110,100,111,99,107,104,117,115,104,45,116,101,109,112,111,255};

struct MetaData { const void *data; size_t size; };
static NSString *adapterPath;
static NSString *supportPath;
static NSTimer *timer;
static void applyDockRule() {
 @autoreleasepool {
  if (!NSApp || ![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.edifier.connectHD"]) return;
  NSData *data=[NSData dataWithContentsOfFile:[supportPath stringByAppendingPathComponent:@"rules.json"]];
  NSDictionary *rules=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  NSArray *dock=[rules[@"dock"] isKindOfClass:[NSArray class]] ? rules[@"dock"] : @[];
  BOOL hidden=[dock containsObject:@"com.edifier.connectHD"];
  NSApplicationActivationPolicy target=hidden ? NSApplicationActivationPolicyAccessory : NSApplicationActivationPolicyRegular;
  if (NSApp.activationPolicy != target) [NSApp setActivationPolicy:target];
  NSRunningApplication *app=NSRunningApplication.currentApplication;
  NSDictionary *state=@{@"pid":@(getpid()),@"adapterVersion":@1,@"adapterPath":adapterPath ?: @"",
    @"launchTime":@(app.launchDate.timeIntervalSince1970),@"updatedAt":@([NSDate date].timeIntervalSince1970),
    @"hidden":@(hidden),@"policy":@(NSApp.activationPolicy)};
  NSData *encoded=[NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
  NSString *session=[supportPath stringByAppendingPathComponent:@"tempo-session.json"];
  [encoded writeToFile:session options:NSDataWritingAtomic error:nil];
  [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:session error:nil];
 }
}
extern "C" __attribute__((visibility("default"))) MetaData qt_plugin_query_metadata_v2() {
 return {qt_metadata+12,sizeof(qt_metadata)-12};
}
extern "C" __attribute__((visibility("default"))) void *qt_plugin_instance() {
 static dispatch_once_t once;
 dispatch_once(&once, ^{
  Dl_info info={};
  if (dladdr((void *)&qt_plugin_instance,&info) && info.dli_fname) adapterPath=[[NSString stringWithUTF8String:info.dli_fname] stringByResolvingSymlinksInPath];
  supportPath=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/DockHush"];
  dispatch_async(dispatch_get_main_queue(), ^{
   timer=[NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *) {applyDockRule();}];
   [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
   applyDockRule();
  });
 });
 // This adapter only bootstraps runtime controls; use the original native theme.
 return nullptr;
}
