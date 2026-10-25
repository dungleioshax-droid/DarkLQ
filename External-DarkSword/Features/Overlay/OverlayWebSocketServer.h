//
//  OverlayWebSocketServer.h
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/27/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^OverlayWebSocketMessageHandler)(NSString *message);
typedef void (^OverlayWebSocketConnectionHandler)(NSUInteger clientCount);

@interface OverlayWebSocketServer : NSObject

@property(nonatomic, assign, readonly) uint16_t port;
@property(nonatomic, assign, readonly) NSUInteger clientCount;
@property(nonatomic, copy, nullable)
    OverlayWebSocketMessageHandler messageHandler;
@property(nonatomic, copy, nullable)
    OverlayWebSocketConnectionHandler connectionHandler;

+ (instancetype)sharedServer;
- (BOOL)start;
- (void)broadcastTextData:(NSData *)data;
- (void)broadcastText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
