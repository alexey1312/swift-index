// Sample Objective-C file for testing

#import <Foundation/Foundation.h>

@interface SampleClass : NSObject

@property (nonatomic, strong) NSString *name;
@property (nonatomic, assign) NSInteger age;

- (instancetype)initWithName:(NSString *)name age:(NSInteger)age;
- (NSString *)greet;

@end

@implementation SampleClass

- (instancetype)initWithName:(NSString *)name age:(NSInteger)age {
    self = [super init];
    if (self) {
        _name = name;
        _age = age;
    }
    return self;
}

- (NSString *)greet {
    return [NSString stringWithFormat:@"Hello, my name is %@", self.name];
}

@end

// Category for testing
@interface SampleClass (Utilities)

- (void)logDetails;

@end

@implementation SampleClass (Utilities)

- (void)logDetails {
    NSLog(@"Name: %@, Age: %ld", self.name, (long)self.age);
}

@end
