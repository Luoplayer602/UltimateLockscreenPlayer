#import "ULPRootListController.h"
#import <Preferences/PSSpecifier.h>

@implementation ULPRootListController

- (void)openGitHub {
    NSURL *url = [NSURL URLWithString:@"https://github.com/luoplayer602"];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        for (PSSpecifier *specifier in _specifiers) {
            NSString *buttonAction = [specifier propertyForKey:@"buttonAction"];
            if (specifier.cellType == PSButtonCell && buttonAction.length) {
                specifier.target = self;
                specifier.buttonAction = NSSelectorFromString(buttonAction);
            }
        }
    }
    return _specifiers;
}

@end
