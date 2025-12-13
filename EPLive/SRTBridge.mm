//
//  SRTBridge.mm
//  EPLive
//
//  SRT Bridge Implementation
//

#import "EPLive-Bridging-Header.h"
#import <arpa/inet.h>

@implementation SRTConfig
- (instancetype)init {
    if (self = [super init]) {
        _latency = 120;
        _maxBandwidth = 0;
        _pbkeylen = 0;
    }
    return self;
}
@end

@implementation SRTWrapper {
    SRTSOCKET _socket;
    SRTStatus _status;
}

- (instancetype)init {
    if (self = [super init]) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            srt_startup();
        });
        _socket = SRT_INVALID_SOCK;
        _status = SRTStatusDisconnected;
    }
    return self;
}

- (BOOL)connectWithConfig:(SRTConfig *)config error:(NSError **)error {
    // Create SRT socket
    _socket = srt_create_socket();
    if (_socket == SRT_INVALID_SOCK) {
        if (error) {
            *error = [NSError errorWithDomain:@"SRTWrapper"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create SRT socket"}];
        }
        return NO;
    }
    
    // Set socket options
    int yes = 1;
    srt_setsockopt(_socket, 0, SRTO_SENDER, &yes, sizeof(yes));
    
    // Use LIVE mode (default) for low-latency streaming
    // LIVE mode requires payloads <= SRTO_PAYLOADSIZE (default 1316)
    // We'll handle chunking in application layer
    
    // Enable timestamp-based packet delivery
    yes = 1;
    srt_setsockopt(_socket, 0, SRTO_TSBPDMODE, &yes, sizeof(yes));
    
    // Increase send buffer to 16MB to prevent packet drops
    int sendBuf = 16 * 1024 * 1024;
    srt_setsockopt(_socket, 0, SRTO_SNDBUF, &sendBuf, sizeof(sendBuf));
    
    // Increase receive buffer
    int recvBuf = 16 * 1024 * 1024;
    srt_setsockopt(_socket, 0, SRTO_RCVBUF, &recvBuf, sizeof(recvBuf));
    
    // Set connection timeout to 5 seconds
    int connectTimeout = 5000;
    srt_setsockopt(_socket, 0, SRTO_CONNTIMEO, &connectTimeout, sizeof(connectTimeout));
    
    // Set latency
    int latency = config.latency;
    srt_setsockopt(_socket, 0, SRTO_LATENCY, &latency, sizeof(latency));
    
    // Set max bandwidth if specified
    if (config.maxBandwidth > 0) {
        int64_t maxbw = config.maxBandwidth;
        srt_setsockopt(_socket, 0, SRTO_MAXBW, &maxbw, sizeof(maxbw));
    }
    
    // Set encryption if passphrase provided
    if (config.passphrase && config.pbkeylen > 0) {
        const char *passphrase = [config.passphrase UTF8String];
        srt_setsockopt(_socket, 0, SRTO_PASSPHRASE, passphrase, (int)strlen(passphrase));
        int keylen = config.pbkeylen;
        srt_setsockopt(_socket, 0, SRTO_PBKEYLEN, &keylen, sizeof(keylen));
    }
    
    // Set streamid for SRS (format: #!::r=live/stream,m=publish)
    if (config.streamid) {
        const char *streamid = [config.streamid UTF8String];
        srt_setsockopt(_socket, 0, SRTO_STREAMID, streamid, (int)strlen(streamid));
    }
    
    // Configure address
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_port = htons(config.port);
    
    if (inet_pton(AF_INET, [config.host UTF8String], &sa.sin_addr) != 1) {
        // Try hostname resolution
        struct hostent *he = gethostbyname([config.host UTF8String]);
        if (he == NULL || he->h_addr_list[0] == NULL) {
            if (error) {
                *error = [NSError errorWithDomain:@"SRTWrapper"
                                             code:-2
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to resolve hostname: %@", config.host]}];
            }
            srt_close(_socket);
            _socket = SRT_INVALID_SOCK;
            return NO;
        }
        memcpy(&sa.sin_addr, he->h_addr_list[0], he->h_length);
    }
    
    // Connect
    _status = SRTStatusConnecting;
    if (srt_connect(_socket, (struct sockaddr *)&sa, sizeof(sa)) == SRT_ERROR) {
        _status = SRTStatusError;
        if (error) {
            const char *errMsg = srt_getlasterror_str();
            *error = [NSError errorWithDomain:@"SRTWrapper"
                                         code:srt_getlasterror(NULL)
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"SRT connection failed: %s", errMsg]}];
        }
        srt_close(_socket);
        _socket = SRT_INVALID_SOCK;
        return NO;
    }
    
    _status = SRTStatusConnected;
    
    // Log socket state for debugging
    SRT_SOCKSTATUS sockStatus = srt_getsockstate(_socket);
    NSLog(@"SRT connected to %@:%d (socket state: %d, latency: %dms)", config.host, config.port, sockStatus, config.latency);
    
    return YES;
}

- (NSInteger)sendData:(NSData *)data error:(NSError **)error {
    if (_socket == SRT_INVALID_SOCK || _status != SRTStatusConnected) {
        if (error) {
            *error = [NSError errorWithDomain:@"SRTWrapper"
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Not connected"}];
        }
        return -1;
    }
    
    // Check socket state before sending
    SRT_SOCKSTATUS sockStatus = srt_getsockstate(_socket);
    if (sockStatus != SRTS_CONNECTED) {
        NSLog(@"⚠️ Socket not in CONNECTED state: %d", sockStatus);
        _status = SRTStatusError;
        if (error) {
            *error = [NSError errorWithDomain:@"SRTWrapper"
                                         code:-5
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Socket in invalid state: %d", sockStatus]}];
        }
        return -1;
    }
    
    const char *buf = (const char *)[data bytes];
    int dataLen = (int)data.length;
    
    // SRT LIVE mode: max payload per packet is 1316 bytes
    // We must chunk manually to respect MTU
    const int MAX_PAYLOAD = 1316;
    int totalSent = 0;
    int offset = 0;
    
    while (offset < dataLen) {
        int chunkSize = MIN(MAX_PAYLOAD, dataLen - offset);
        int sent = srt_send(_socket, buf + offset, chunkSize);
        
        if (sent == SRT_ERROR) {
            int srtError = srt_getlasterror(NULL);
            const char *errMsg = srt_getlasterror_str();
            
            NSLog(@"❌ SRT send error: %s (code: %d, socket state: %d)", errMsg, srtError, srt_getsockstate(_socket));
            
            // Check if connection is broken
            if (srtError == SRT_ECONNLOST || sockStatus != SRTS_CONNECTED) {
                _status = SRTStatusError;
            }
            
            if (error) {
                *error = [NSError errorWithDomain:@"SRTWrapper"
                                             code:srtError
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Send failed: %s", errMsg]}];
            }
            return -1;
        }
        
        offset += sent;
        totalSent += sent;
        
        // If we didn't send the full chunk, something is wrong
        if (sent < chunkSize && offset < dataLen) {
            NSLog(@"⚠️ Partial send: %d/%d bytes (offset: %d/%d)", sent, chunkSize, offset, dataLen);
            if (error) {
                *error = [NSError errorWithDomain:@"SRTWrapper"
                                             code:-4
                                         userInfo:@{NSLocalizedDescriptionKey: @"Partial send occurred"}];
            }
            return -1;
        }
    }
    
    return totalSent;
}

- (BOOL)checkConnection {
    if (_socket == SRT_INVALID_SOCK) {
        _status = SRTStatusDisconnected;
        return NO;
    }
    
    SRT_SOCKSTATUS sockStatus = srt_getsockstate(_socket);
    if (sockStatus != SRTS_CONNECTED) {
        NSLog(@"⚠️ Connection check failed: socket state %d", sockStatus);
        _status = SRTStatusError;
        return NO;
    }
    
    return YES;
}

- (NSDictionary *)getStats {
    if (_socket == SRT_INVALID_SOCK) {
        return @{};
    }
    
    SRT_TRACEBSTATS stats;
    if (srt_bstats(_socket, &stats, 1) == SRT_ERROR) {
        NSLog(@"⚠️ Failed to get SRT stats: %s", srt_getlasterror_str());
        return @{};
    }
    
    return @{
        @"pktSent": @(stats.pktSent),
        @"pktSentUnique": @(stats.pktSentUnique),
        @"pktRetrans": @(stats.pktRetrans),
        @"pktSndLoss": @(stats.pktSndLoss),
        @"pktSndDrop": @(stats.pktSndDrop),
        @"byteSent": @(stats.byteSent),
        @"byteRetrans": @(stats.byteRetrans),
        @"byteSndDrop": @(stats.byteSndDrop),
        @"mbpsSendRate": @(stats.mbpsSendRate),
        @"msRTT": @(stats.msRTT),
        @"mbpsBandwidth": @(stats.mbpsBandwidth),
        @"pktCongestionWindow": @(stats.pktCongestionWindow),
        @"pktFlightSize": @(stats.pktFlightSize)
    };
}

- (void)disconnect {
    if (_socket != SRT_INVALID_SOCK) {
        srt_close(_socket);
        _socket = SRT_INVALID_SOCK;
        _status = SRTStatusDisconnected;
        NSLog(@"SRT disconnected");
    }
}

- (void)dealloc {
    [self disconnect];
}

@end
