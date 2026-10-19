// Мост к приватному MediaRemote.framework.
//
// С macOS 15.4 MediaRemote отдаёт данные «Сейчас играет» только процессам Apple,
// поэтому библиотека загружается в системный /usr/bin/perl (см. NowPlaying.pl),
// а приложение читает JSON-строки из его stdout.

#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetPIDFn)(dispatch_queue_t, void (^)(int));
typedef void (*MRGetIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef Boolean (*MRSendCommandFn)(int, CFDictionaryRef);
typedef void (*MRSetElapsedFn)(double);

static void *mr(void) {
    static void *handle;
    if (!handle) {
        handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    }
    return handle;
}

static id jsonValue(id value) {
    if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) return value;
    if ([value isKindOfClass:NSDate.class]) return @([(NSDate *)value timeIntervalSince1970]);
    return nil;
}

static void emit(NSDictionary *payload) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!data) return;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

// Раз в секунду печатает состояние. Обложка отправляется только при её смене.
void nh_stream(void) {
    MRGetInfoFn getInfo = dlsym(mr(), "MRMediaRemoteGetNowPlayingInfo");
    MRGetPIDFn getPID = dlsym(mr(), "MRMediaRemoteGetNowPlayingApplicationPID");
    MRGetIsPlayingFn getIsPlaying = dlsym(mr(), "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    if (!getInfo || !getPID || !getIsPlaying) {
        emit(@{@"error": @"MediaRemote unavailable"});
        return;
    }

    dispatch_queue_t queue = dispatch_queue_create("notchhub.nowplaying", DISPATCH_QUEUE_SERIAL);
    __block NSUInteger lastArtworkHash = 0;

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, NSEC_PER_SEC, NSEC_PER_SEC / 2);
    dispatch_source_set_event_handler(timer, ^{
        getPID(queue, ^(int pid) {
            getIsPlaying(queue, ^(Boolean playing) {
                getInfo(queue, ^(CFDictionaryRef ref) {
                    NSDictionary *info = (__bridge NSDictionary *)ref;
                    NSMutableDictionary *out = [NSMutableDictionary dictionary];
                    out[@"pid"] = @(pid);
                    out[@"playing"] = @(playing);

                    for (NSString *key in info) {
                        if ([key hasSuffix:@"ArtworkData"]) continue;
                        id value = jsonValue(info[key]);
                        NSString *shortKey = [key stringByReplacingOccurrencesOfString:@"kMRMediaRemoteNowPlayingInfo" withString:@""];
                        if (value) out[shortKey] = value;
                    }

                    NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                    if ([artwork isKindOfClass:NSData.class] && artwork.length > 0) {
                        NSUInteger hash = artwork.hash ^ artwork.length;
                        if (hash != lastArtworkHash) {
                            lastArtworkHash = hash;
                            out[@"Artwork"] = [artwork base64EncodedStringWithOptions:0];
                        }
                        out[@"ArtworkHash"] = @(hash);
                    } else {
                        lastArtworkHash = 0;
                    }
                    emit(out);
                });
            });
        });
    });
    dispatch_resume(timer);
    dispatch_main();
}

// Команды уходят по XPC асинхронно — даём им отправиться до выхода процесса.
static void flush(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
}

// Команда из переменной окружения NH_CMD: play, pause, toggle, next, previous, seek:<секунды>.
void nh_send(void) {
    const char *raw = getenv("NH_CMD");
    if (!raw) return;
    NSString *cmd = @(raw);

    if ([cmd hasPrefix:@"seek:"]) {
        MRSetElapsedFn setElapsed = dlsym(mr(), "MRMediaRemoteSetElapsedTime");
        if (setElapsed) setElapsed([[cmd substringFromIndex:5] doubleValue]);
        flush();
        return;
    }

    NSDictionary *codes = @{@"play": @0, @"pause": @1, @"toggle": @2, @"next": @4, @"previous": @5};
    NSNumber *code = codes[cmd];
    MRSendCommandFn send = dlsym(mr(), "MRMediaRemoteSendCommand");
    if (code && send) send(code.intValue, NULL);
    flush();
}
