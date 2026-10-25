//
//  AoVHeroNameResolver.m
//  External-DarkSword
//
//  Created by Le Tien Dat on 8/28/26.
//

#import "AoVHeroNameResolver.h"
#import "../../../../App/Configuration/AppURLs.h"
#import "../../../../App/Configuration/Macros.h"

/// Remove lines comment contain in file json
static NSData *JSONDataByRemovingLeadingComments(NSData *data) {
    NSString *payload = [[NSString alloc] initWithData:data
                                              encoding:NSUTF8StringEncoding];
    if (!payload) {
        return nil;
    }

    NSCharacterSet *whitespace =
        [NSCharacterSet whitespaceAndNewlineCharacterSet];
    while (true) {
        payload = [payload stringByTrimmingCharactersInSet:whitespace];

        if ([payload hasPrefix:@"\uFEFF"]) {
            payload = [payload substringFromIndex:1];
            continue;
        }

        if ([payload hasPrefix:@"/*"]) {
            NSRange end =
                [payload rangeOfString:@"*/"
                               options:0
                                 range:NSMakeRange(2, payload.length - 2)];
            if (end.location == NSNotFound) {
                return nil;
            }
            payload = [payload substringFromIndex:NSMaxRange(end)];
            continue;
        }

        if ([payload hasPrefix:@"//"]) {
            NSRange lineEnd = [payload
                rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]];
            if (lineEnd.location == NSNotFound) {
                return nil;
            }
            payload = [payload substringFromIndex:NSMaxRange(lineEnd)];
            continue;
        }

        break;
    }

    return [payload dataUsingEncoding:NSUTF8StringEncoding];
}

@interface AoVHeroNameResolver ()

@property(nonatomic, copy) NSDictionary<NSNumber *, NSString *> *heroNames;
@property(nonatomic, assign) BOOL isLoading;
@property(nonatomic, assign) BOOL hasLoaded;

@end

@implementation AoVHeroNameResolver

+ (instancetype)sharedResolver {
    static AoVHeroNameResolver *resolver;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      resolver = [[self alloc] init];
    });
    return resolver;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _heroNames = @{};
        _isLoading = NO;
        _hasLoaded = NO;
    }
    return self;
}

- (void)loadFromRemote {
    @synchronized(self) {
        if (self.isLoading || self.hasLoaded) {
            return;
        }
        self.isLoading = YES;
    }

    NSURL *url = [NSURL URLWithString:kAoVHeroInfoURL];
    if (!url) {
        @synchronized(self) {
            self.isLoading = NO;
        }
        LOG(@"[AoV] Hero info URL is invalid.");
        return;
    }

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
          dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response,
                            NSError *error) {
          if (error) {
              [self finishLoadingWithHeroNames:nil
                                  errorMessage:error.localizedDescription];
              return;
          }

          NSHTTPURLResponse *httpResponse =
              [response isKindOfClass:[NSHTTPURLResponse class]]
                  ? (NSHTTPURLResponse *)response
                  : nil;
          if (!data || httpResponse.statusCode < 200 ||
              httpResponse.statusCode >= 300) {
              NSString *message = [NSString
                  stringWithFormat:@"HTTP %ld", (long)httpResponse.statusCode];
              [self finishLoadingWithHeroNames:nil errorMessage:message];
              return;
          }

          NSData *jsonData = JSONDataByRemovingLeadingComments(data);
          if (!jsonData) {
              [self finishLoadingWithHeroNames:nil
                                  errorMessage:@"Invalid UTF-8 or malformed "
                                               @"leading comment"];
              return;
          }

          NSError *jsonError = nil;
          id json = [NSJSONSerialization JSONObjectWithData:jsonData
                                                    options:0
                                                      error:&jsonError];
          if (jsonError || ![json isKindOfClass:[NSArray class]]) {
              [self finishLoadingWithHeroNames:nil
                                  errorMessage:jsonError.localizedDescription];
              return;
          }

          NSMutableDictionary<NSNumber *, NSString *> *heroNames =
              [NSMutableDictionary dictionary];
          for (id value in (NSArray *)json) {
              if (![value isKindOfClass:[NSDictionary class]]) {
                  continue;
              }

              NSDictionary *hero = (NSDictionary *)value;
              id heroIDValue = hero[@"heroID"];
              id heroNameValue = hero[@"heroName"];
              if (![heroIDValue isKindOfClass:[NSNumber class]] ||
                  ![heroNameValue isKindOfClass:[NSString class]]) {
                  continue;
              }

              NSInteger heroID = [heroIDValue integerValue];
              NSString *heroName = [(NSString *)heroNameValue
                  stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
              if (heroID <= 0 || heroName.length == 0) {
                  continue;
              }
              heroNames[@(heroID)] = heroName;
          }

          if (heroNames.count == 0) {
              [self finishLoadingWithHeroNames:nil
                                  errorMessage:@"No valid hero entries"];
              return;
          }
          [self finishLoadingWithHeroNames:heroNames errorMessage:nil];
        }];
    [task resume];
}

- (NSString *)heroNameForID:(int)heroID {
    NSDictionary<NSNumber *, NSString *> *heroNames;
    @synchronized(self) {
        heroNames = self.heroNames;
    }

    NSString *name = heroNames[@(heroID)];
    return name ?: [NSString stringWithFormat:@"%d", heroID];
}

- (void)finishLoadingWithHeroNames:
            (nullable NSDictionary<NSNumber *, NSString *> *)heroNames
                      errorMessage:(nullable NSString *)errorMessage {
    @synchronized(self) {
        self.isLoading = NO;
        if (heroNames) {
            self.heroNames = [heroNames copy];
            self.hasLoaded = YES;
        }
    }

    if (heroNames) {
        LOG(@"[AoV] Loaded %lu hero names from remote data.",
            (unsigned long)heroNames.count);
    } else {
        LOG(@"[AoV] Failed to load hero names: %@",
            errorMessage ?: @"Unknown error");
    }
}

@end
