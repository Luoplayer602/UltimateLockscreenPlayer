#import "ULPVisualizerListController.h"
#import "ULPVisualizerPreviewController.h"
#import "ULPModePickerController.h"
#import "../Visualization/ULPVisualPreferences.h"
#import <Preferences/PSSpecifier.h>
#import <CoreFoundation/CoreFoundation.h>

@interface ULPVisualizerListController () {
    ULPVisualizerPreviewController *_stickyPreview;
    UIView *_previewHeader;
    UIView *_previewSpacer;
    ULPVisualMode _loadedMode;
}
@end

@implementation ULPVisualizerListController

- (void)recordPreviewIssue:(NSString *)message {
    [message writeToFile:@"/var/mobile/Library/Logs/ULPPreferences.log"
             atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (UITableView *)tableInsideView:(UIView *)view {
    if ([view isKindOfClass:UITableView.class]) return (UITableView *)view;
    for (UIView *subview in view.subviews) {
        UITableView *table = [self tableInsideView:subview];
        if (table) return table;
    }
    return nil;
}

- (UITableView *)settingsTable {
    return [self tableInsideView:self.view];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _stickyPreview = [ULPVisualizerPreviewController new];
    _stickyPreview.compact = YES;
    [self addChildViewController:_stickyPreview];
    _previewHeader = [[UIView alloc] initWithFrame:CGRectMake(0, 0,
        CGRectGetWidth(self.view.bounds), 200)];
    _previewSpacer = [[UIView alloc] initWithFrame:_previewHeader.bounds];
    [_previewHeader addSubview:_stickyPreview.view];
    [_stickyPreview didMoveToParentViewController:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    ULPMigrateVisualPreferences();
    if (_specifiers && ULPLoadVisualPreferences().mode != _loadedMode) {
        _specifiers = nil;
        [self reloadSpecifiers];
    }
    @try {
        UITableView *table = [self settingsTable];
        if (table && table.tableHeaderView != _previewSpacer)
            table.tableHeaderView = _previewSpacer;
        [self positionStickyPreview];
        [_stickyPreview startPreviewRendering];
    } @catch (NSException *exception) {
        [self recordPreviewIssue:[NSString stringWithFormat:@"viewWillAppear: %@ %@\n",
            exception.name, exception.reason]];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    @try {
        [self positionStickyPreview];
    } @catch (NSException *exception) {
        [self recordPreviewIssue:[NSString stringWithFormat:@"layout: %@ %@\n",
            exception.name, exception.reason]];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_stickyPreview stopPreviewRendering];
}

- (void)positionStickyPreview {
    UITableView *table = [self settingsTable];
    if (!table) return;
    CGFloat width = CGRectGetWidth(table.bounds);
    if (fabs(CGRectGetWidth(_previewSpacer.bounds) - width) > 1) {
        _previewSpacer.frame = CGRectMake(0, 0, width, 200);
        table.tableHeaderView = _previewSpacer;
    }
    _stickyPreview.view.frame = CGRectMake(16, 8, width - 32, 184);
    [self scrollViewDidScroll:table];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    @try {
        UITableView *table = [self settingsTable];
        if (scrollView != table || !_previewHeader) return;
        // A translated table header can be culled once its original row scrolls away.
        // Keep the interactive preview outside the scroll view; reserve its space above.
        UIView *host = table.superview;
        if (!host) return;
        if (_previewHeader.superview != host) [host addSubview:_previewHeader];
        CGRect visibleTop = CGRectMake(scrollView.bounds.origin.x,
            scrollView.bounds.origin.y + scrollView.adjustedContentInset.top,
            CGRectGetWidth(scrollView.bounds), 200);
        _previewHeader.frame = [table convertRect:visibleTop toView:host];
        _previewHeader.backgroundColor = table.backgroundColor ?: UIColor.systemBackgroundColor;
        [host bringSubviewToFront:_previewHeader];
    } @catch (NSException *exception) {
        [self recordPreviewIssue:[NSString stringWithFormat:@"scroll: %@ %@\n",
            exception.name, exception.reason]];
    }
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        ULPMigrateVisualPreferences();
        _loadedMode = ULPLoadVisualPreferences().mode;
        NSString *path = [[NSBundle bundleForClass:self.class] pathForResource:@"Visualizer" ofType:@"plist"];
        NSArray *items = [NSDictionary dictionaryWithContentsOfFile:path][@"items"];
        NSMutableDictionary *definitions = [NSMutableDictionary dictionary];
        for (NSDictionary *item in items) {
            if (item[@"id"]) definitions[item[@"id"]] = item;
        }
        NSArray *loaded = [self loadSpecifiersFromPlistName:@"Visualizer" target:self];
        _specifiers = [NSMutableArray array];
        for (PSSpecifier *specifier in loaded) {
            // Match stable IDs, never array indexes: Preferences may transform its input.
            NSDictionary *item = definitions[specifier.identifier ?: @""];
            if (!item) {
                [self recordPreviewIssue:[NSString stringWithFormat:@"Missing definition: %@", specifier.identifier]];
                continue;
            }
            NSArray *modes = item[@"ulpModes"];
            if (modes && ![modes containsObject:@(_loadedMode)]) continue;
            for (NSString *property in item) {
                if ([property hasPrefix:@"ulp"])
                    [specifier setProperty:item[property] forKey:property];
            }
            NSString *key = item[@"key"];
            if (key) {
                [specifier setProperty:key forKey:@"ulpOriginalKey"];
                [specifier setProperty:ULPVisualPreferenceKey(key, _loadedMode) forKey:@"key"];
            }
            NSString *buttonAction = item[@"buttonAction"];
            if (specifier.cellType == PSButtonCell && buttonAction.length) {
                specifier.target = self;
                specifier.buttonAction = NSSelectorFromString(buttonAction);
            }
            if ([specifier.identifier isEqualToString:@"ULPModePicker"])
                specifier.name = [@"Modes · " stringByAppendingString:ULPModeTitle(_loadedMode)];
            [_specifiers addObject:specifier];
        }
        [self updateDependencies:NO];
    }
    return _specifiers;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if ([specifier.identifier isEqualToString:@"ULPModePicker"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self openModes];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

- (void)openModes {
    [self.navigationController pushViewController:[ULPModePickerController new] animated:YES];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return [specifier propertyForKey:@"default"];
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
        CFSTR("com.luoplayer.ultimatelockscreenplayer"));
    return CFBridgingRelease(value) ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;
    if ([value isKindOfClass:NSNumber.class] && [specifier propertyForKey:@"min"]) {
        double number = [value doubleValue];
        if (!isfinite(number)) number = [[specifier propertyForKey:@"default"] doubleValue];
        number = MAX([[specifier propertyForKey:@"min"] doubleValue],
                     MIN([[specifier propertyForKey:@"max"] doubleValue], number));
        if ([[specifier propertyForKey:@"ulpInteger"] boolValue]) number = round(number);
        value = @(number);
    }
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
        CFSTR("com.luoplayer.ultimatelockscreenplayer"));
    CFPreferencesAppSynchronize(CFSTR("com.luoplayer.ultimatelockscreenplayer"));
    [self updateDependencies:YES];
    [_stickyPreview refreshVisualPreferences];
}

- (void)updateDependencies:(BOOL)reload {
    for (PSSpecifier *dependent in _specifiers) {
        NSString *key = [dependent propertyForKey:@"ulpDependsOn"];
        BOOL inverse = NO;
        if (!key) { key = [dependent propertyForKey:@"ulpDisabledBy"]; inverse = YES; }
        if (!key) continue;
        for (PSSpecifier *source in _specifiers) {
            if (![[source propertyForKey:@"ulpOriginalKey"] isEqualToString:key]) continue;
            BOOL enabled = [[self readPreferenceValue:source] boolValue];
            if (inverse) enabled = !enabled;
            if (![[dependent propertyForKey:@"enabled"] isEqual:@(enabled)]) {
                [dependent setProperty:@(enabled) forKey:@"enabled"];
                if (reload) [self reloadSpecifier:dependent animated:NO];
            }
            break;
        }
    }
}

- (void)resetPosition {
    for (NSString *key in @[@"VisualOffsetX", @"VisualOffsetY", @"VisualWidth", @"VisualHeight",
                            @"VisualScale", @"VisualRotation", @"VisualFlipX", @"VisualFlipY"])
        CFPreferencesSetAppValue((__bridge CFStringRef)ULPVisualPreferenceKey(key, _loadedMode),
                                 NULL, CFSTR("com.luoplayer.ultimatelockscreenplayer"));
    CFPreferencesAppSynchronize(CFSTR("com.luoplayer.ultimatelockscreenplayer"));
    CGPoint offset = [self settingsTable].contentOffset;
    _specifiers = nil;
    [self reloadSpecifiers];
    [[self settingsTable] layoutIfNeeded];
    [[self settingsTable] setContentOffset:offset animated:NO];
    [_stickyPreview refreshVisualPreferences];
}

@end
