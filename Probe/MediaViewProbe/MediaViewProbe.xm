#import <UIKit/UIKit.h>
#import <fcntl.h>
#import <unistd.h>

@interface CSMediaControlsView : UIView
@end

static void ULPProbeLog(NSString *message) {
    NSString *line = [NSString stringWithFormat:@"%@\n", message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    int fd = open("/var/mobile/Library/Logs/ULP-MediaView.log",
                  O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (fd < 0) return;
    (void)write(fd, data.bytes, data.length);
    close(fd);
}

static BOOL ULPProbeIsLockScreen(UIView *view) {
    for (UIView *ancestor = view.superview; ancestor; ancestor = ancestor.superview)
        if ([NSStringFromClass(ancestor.class) isEqualToString:@"CSCoverSheetView"])
            return YES;
    return NO;
}

static void ULPProbeTree(UIView *view, UIView *root, unsigned depth,
                         unsigned *count) {
    if (!view || depth > 7 || *count > 180) return;
    CGRect rect = [view convertRect:view.bounds toView:root];
    NSString *extra = @"";
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImage *image = ((UIImageView *)view).image;
        extra = [NSString stringWithFormat:@" image=%d", image != nil];
    }
    ULPProbeLog([NSString stringWithFormat:
        @"d=%u %@ frame=(%.0f,%.0f,%.0f,%.0f) bounds=(%.0f,%.0f) inRoot=(%.0f,%.0f,%.0f,%.0f) hidden=%d%@",
        depth, NSStringFromClass(view.class), view.frame.origin.x, view.frame.origin.y,
        view.frame.size.width, view.frame.size.height,
        view.bounds.size.width, view.bounds.size.height,
        rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
        view.hidden, extra]);
    ++*count;
    for (UIView *child in view.subviews) ULPProbeTree(child, root, depth + 1, count);
}

%hook CSMediaControlsView

- (void)layoutSubviews {
    %orig;
    static BOOL scheduled;
    if (scheduled || !ULPProbeIsLockScreen(self)) return;
    scheduled = YES;
    __weak UIView *weakView = self;
    const unsigned delays[] = {2, 6, 12, 20};
    for (unsigned index = 0; index < sizeof(delays) / sizeof(delays[0]); ++index) {
        unsigned delay = delays[index];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            UIView *view = weakView;
            if (!view) return;
            ULPProbeLog([NSString stringWithFormat:@"BEGIN native lockscreen media view t=%us", delay]);
            UIView *ancestor = view;
            for (unsigned depth = 0; ancestor && depth < 10; ++depth, ancestor = ancestor.superview)
                ULPProbeLog([NSString stringWithFormat:@"ancestor=%u %@ frame=%@ bounds=%@ transform=%@",
                    depth, NSStringFromClass(ancestor.class), NSStringFromCGRect(ancestor.frame),
                    NSStringFromCGRect(ancestor.bounds), NSStringFromCGAffineTransform(ancestor.transform)]);
            UIView *item = view.superview.superview.superview;
            UIStackView *stack = [item.superview isKindOfClass:[UIStackView class]] ?
                                 (UIStackView *)item.superview : nil;
            if (stack) {
                ULPProbeLog([NSString stringWithFormat:
                    @"stack arranged=%lu subviews=%lu axis=%ld spacing=%.1f margins=%@ relative=%d",
                    (unsigned long)stack.arrangedSubviews.count,
                    (unsigned long)stack.subviews.count, (long)stack.axis,
                    stack.spacing, NSStringFromUIEdgeInsets(stack.layoutMargins),
                    stack.layoutMarginsRelativeArrangement]);
                for (UIView *child in stack.subviews)
                    ULPProbeLog([NSString stringWithFormat:
                        @"stack child %@ frame=%@ hidden=%d arranged=%d",
                        NSStringFromClass(child.class), NSStringFromCGRect(child.frame),
                        child.hidden, [stack.arrangedSubviews containsObject:child]]);
            }
            UIScrollView *list = [stack.superview isKindOfClass:[UIScrollView class]] ?
                                 (UIScrollView *)stack.superview : nil;
            if (list)
                ULPProbeLog([NSString stringWithFormat:
                    @"list offset=%@ inset=%@ contentSize=%@",
                    NSStringFromCGPoint(list.contentOffset),
                    NSStringFromUIEdgeInsets(list.contentInset),
                    NSStringFromCGSize(list.contentSize)]);
            unsigned count = 0;
            ULPProbeTree(view, view, 0, &count);
            ULPProbeLog([NSString stringWithFormat:@"END t=%us views=%u", delay, count]);
        });
    }
}

%end
