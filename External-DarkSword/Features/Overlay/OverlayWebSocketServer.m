//
//  OverlayWebSocketServer.m
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/27/26.
//

#import "OverlayWebSocketServer.h"
#import "../../App/Configuration/Config.h"
#import "../../App/Configuration/Macros.h"
#import <CommonCrypto/CommonDigest.h>
#import <CoreFoundation/CoreFoundation.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <netinet/tcp.h>
#import <sys/socket.h>
#import <unistd.h>

static const uint16_t kOverlayWebSocketDefaultPort = 17391;
static NSString *const kOverlayWebSocketGUID =
    @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

@interface OverlayWebSocketServer ()

@property(nonatomic, assign, readwrite) uint16_t port;
@property(nonatomic, assign) int listenFD;
@property(nonatomic, assign) BOOL running;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *clients;
@property(nonatomic, strong) NSLock *clientsLock;
@property(nonatomic, strong) NSLock *writeLock;
@property(nonatomic, strong) dispatch_queue_t ioQueue;

@end

@implementation OverlayWebSocketServer

+ (instancetype)sharedServer {
    static OverlayWebSocketServer *server = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      server = [[OverlayWebSocketServer alloc] init];
    });
    return server;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _listenFD = -1;
        _clients = [NSMutableSet set];
        _clientsLock = [NSLock new];
        _writeLock = [NSLock new];
        _ioQueue = dispatch_queue_create("com.darksword.overlay.websocket",
                                         DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (NSUInteger)clientCount {
    [self.clientsLock lock];
    NSUInteger count = self.clients.count;
    [self.clientsLock unlock];
    return count;
}

- (BOOL)start {
    @synchronized(self) {
        if (self.running && self.listenFD >= 0)
            return YES;

        for (uint16_t port = kOverlayWebSocketDefaultPort;
             port < kOverlayWebSocketDefaultPort + 20; port++) {
            int fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
            if (fd < 0)
                continue;

            int yes = 1;
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
#ifdef SO_NOSIGPIPE
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
#endif
            setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &yes, sizeof(yes));

            struct sockaddr_in addr = {};
            addr.sin_len = sizeof(addr);
            addr.sin_family = AF_INET;
            addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            addr.sin_port = htons(port);

            if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0 &&
                listen(fd, 4) == 0) {
                self.listenFD = fd;
                self.port = port;
                self.running = YES;
                [self startAcceptLoop];
                LOG(@"[OverlayWS] Listening on ws://127.0.0.1:%u", self.port);
                return YES;
            }

            close(fd);
        }
    }

    LOG(@"[OverlayWS] Failed to bind local WebSocket port");
    return NO;
}

- (void)startAcceptLoop {
    dispatch_async(self.ioQueue, ^{
      while (self.running && self.listenFD >= 0) {
          struct sockaddr_in addr = {};
          socklen_t addrLen = sizeof(addr);
          int clientFD =
              accept(self.listenFD, (struct sockaddr *)&addr, &addrLen);
          if (clientFD < 0)
              continue;

          int yes = 1;
#ifdef SO_NOSIGPIPE
          setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
#endif
          setsockopt(clientFD, IPPROTO_TCP, TCP_NODELAY, &yes, sizeof(yes));
          struct timeval sendTimeout = {};
          sendTimeout.tv_usec = 5000;
          setsockopt(clientFD, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout,
                     sizeof(sendTimeout));

          dispatch_async(self.ioQueue, ^{
            [self handleClient:clientFD];
          });
      }
    });
}

- (void)handleClient:(int)clientFD {
    if (![self performHandshake:clientFD]) {
        close(clientFD);
        return;
    }

    NSNumber *client = @(clientFD);
    [self.clientsLock lock];
    [self.clients addObject:client];
    NSUInteger count = self.clients.count;
    [self.clientsLock unlock];
    LOG(@"[OverlayWS] Client connected fd=%d clients=%lu", clientFD,
        (unsigned long)count);
    if (self.connectionHandler)
        self.connectionHandler(count);

    [self readClientLoop:clientFD];

    [self.clientsLock lock];
    [self.clients removeObject:client];
    count = self.clients.count;
    [self.clientsLock unlock];
    close(clientFD);
    LOG(@"[OverlayWS] Client disconnected fd=%d clients=%lu", clientFD,
        (unsigned long)count);
    if (self.connectionHandler)
        self.connectionHandler(count);
}

- (BOOL)performHandshake:(int)clientFD {
    NSMutableData *request = [NSMutableData data];
    uint8_t buffer[1024];

    while (request.length < 8192) {
        ssize_t n = recv(clientFD, buffer, sizeof(buffer), 0);
        if (n <= 0)
            return NO;
        [request appendBytes:buffer length:(NSUInteger)n];

        NSString *text = [[NSString alloc] initWithData:request
                                               encoding:NSUTF8StringEncoding];
        if ([text containsString:@"\r\n\r\n"]) {
            NSString *key = [self webSocketKeyFromRequest:text];
            if (key.length == 0)
                return NO;

            NSString *accept = [self webSocketAcceptForKey:key];
            NSString *response = [NSString
                stringWithFormat:@"HTTP/1.1 101 Switching Protocols\r\n"
                                 @"Upgrade: websocket\r\n"
                                 @"Connection: Upgrade\r\n"
                                 @"Sec-WebSocket-Accept: %@\r\n\r\n",
                                 accept];
            NSData *responseData =
                [response dataUsingEncoding:NSUTF8StringEncoding];
            return [self writeAll:clientFD data:responseData];
        }
    }

    return NO;
}

- (NSString *)webSocketKeyFromRequest:(NSString *)request {
    NSArray<NSString *> *lines = [request componentsSeparatedByString:@"\r\n"];
    for (NSString *line in lines) {
        NSRange colon = [line rangeOfString:@":"];
        if (colon.location == NSNotFound)
            continue;

        NSString *name =
            [[line substringToIndex:colon.location] lowercaseString];
        if (![name isEqualToString:@"sec-websocket-key"])
            continue;

        NSString *value = [line substringFromIndex:colon.location + 1];
        return [value stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return nil;
}

- (NSString *)webSocketAcceptForKey:(NSString *)key {
    NSString *input = [key stringByAppendingString:kOverlayWebSocketGUID];
    NSData *inputData = [input dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(inputData.bytes, (CC_LONG)inputData.length, digest);
    NSData *digestData = [NSData dataWithBytes:digest length:sizeof(digest)];
    return [digestData base64EncodedStringWithOptions:0];
}

- (void)readClientLoop:(int)clientFD {
    uint8_t header[2];
    while (self.running) {
        if (![self readAll:clientFD buffer:header length:sizeof(header)])
            break;

        uint8_t opcode = header[0] & 0x0f;
        BOOL masked = (header[1] & 0x80) != 0;
        uint64_t length = header[1] & 0x7f;
        if (length == 126) {
            uint8_t ext[2];
            if (![self readAll:clientFD buffer:ext length:sizeof(ext)])
                break;
            length = ((uint64_t)ext[0] << 8) | ext[1];
        } else if (length == 127) {
            uint8_t ext[8];
            if (![self readAll:clientFD buffer:ext length:sizeof(ext)])
                break;
            length = 0;
            for (int i = 0; i < 8; i++)
                length = (length << 8) | ext[i];
        }

        if (length > 65536)
            break;

        uint8_t mask[4] = {};
        if (masked && ![self readAll:clientFD buffer:mask length:sizeof(mask)])
            break;

        NSMutableData *payload =
            [NSMutableData dataWithLength:(NSUInteger)length];
        if (length > 0 && ![self readAll:clientFD
                                  buffer:payload.mutableBytes
                                  length:(size_t)length])
            break;

        if (masked) {
            uint8_t *bytes = (uint8_t *)payload.mutableBytes;
            for (NSUInteger i = 0; i < payload.length; i++)
                bytes[i] ^= mask[i % 4];
        }

        if (opcode == 0x8) {
            [self sendFrameToClient:clientFD opcode:0x8 payload:nil];
            break;
        }
        if (opcode == 0x9) {
            [self sendFrameToClient:clientFD opcode:0xA payload:payload];
        } else if (opcode == 0x1 && payload.length > 0) {
            NSString *message =
                [[NSString alloc] initWithData:payload
                                      encoding:NSUTF8StringEncoding];
            if (g_isDebug)
                LOG(@"[OverlayWS] Client message: %@",
                    message ?: @"<non-utf8>");
            if (message.length > 0 && self.messageHandler)
                self.messageHandler(message);
        }
    }
}

- (void)broadcastText:(NSString *)text {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    [self broadcastTextData:data];
}

- (void)broadcastTextData:(NSData *)data {
    if (data.length == 0)
        return;

    [self.clientsLock lock];
    NSArray<NSNumber *> *clients = [self.clients allObjects];
    [self.clientsLock unlock];

    if (clients.count == 0)
        return;

    for (NSNumber *client in clients) {
        int fd = client.intValue;
        if (![self sendFrameToClient:fd opcode:0x1 payload:data]) {
            [self.clientsLock lock];
            [self.clients removeObject:client];
            [self.clientsLock unlock];
            close(fd);
        }
    }
}

- (BOOL)sendFrameToClient:(int)clientFD
                   opcode:(uint8_t)opcode
                  payload:(NSData *)payload {
    NSUInteger length = payload.length;
    NSMutableData *frame = [NSMutableData dataWithCapacity:length + 10];
    uint8_t first = 0x80 | (opcode & 0x0f);
    [frame appendBytes:&first length:1];

    if (length < 126) {
        uint8_t len = (uint8_t)length;
        [frame appendBytes:&len length:1];
    } else if (length <= UINT16_MAX) {
        uint8_t marker = 126;
        uint16_t len = htons((uint16_t)length);
        [frame appendBytes:&marker length:1];
        [frame appendBytes:&len length:sizeof(len)];
    } else {
        uint8_t marker = 127;
        uint64_t len = CFSwapInt64HostToBig((uint64_t)length);
        [frame appendBytes:&marker length:1];
        [frame appendBytes:&len length:sizeof(len)];
    }

    if (payload.length > 0)
        [frame appendData:payload];

    [self.writeLock lock];
    BOOL didWrite = [self writeAll:clientFD data:frame];
    [self.writeLock unlock];
    return didWrite;
}

- (BOOL)readAll:(int)fd buffer:(void *)buffer length:(size_t)length {
    uint8_t *cursor = (uint8_t *)buffer;
    size_t remaining = length;
    while (remaining > 0) {
        ssize_t n = recv(fd, cursor, remaining, 0);
        if (n <= 0)
            return NO;
        cursor += n;
        remaining -= (size_t)n;
    }
    return YES;
}

- (BOOL)writeAll:(int)fd data:(NSData *)data {
    const uint8_t *cursor = (const uint8_t *)data.bytes;
    size_t remaining = data.length;
    while (remaining > 0) {
        ssize_t n = send(fd, cursor, remaining, 0);
        if (n <= 0)
            return NO;
        cursor += n;
        remaining -= (size_t)n;
    }
    return YES;
}

@end
