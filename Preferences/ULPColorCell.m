#import "ULPColorCell.h"
#import <Preferences/PSSpecifier.h>
#import "../UI/ULPStyleColors.h"
@implementation ULPColorCell {
    UILabel *_hexLabel;
    UIView *_swatch;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (!self) return nil;
    _hexLabel = [UILabel new];
    _hexLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    _hexLabel.textColor = UIColor.secondaryLabelColor;
    _hexLabel.textAlignment = NSTextAlignmentRight;
    _swatch = [UIView new];
    _swatch.layer.cornerRadius = 12;
    _swatch.layer.borderWidth = 1;
    _swatch.layer.borderColor = [UIColor colorWithWhite:1 alpha:.3].CGColor;
    [self.contentView addSubview:_hexLabel];
    [self.contentView addSubview:_swatch];
    [self refreshCellContentsWithSpecifier:specifier];
    return self;
}
- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    self.specifier = specifier;
    if (!_hexLabel) return;
    id value = [specifier performGetter] ?: [specifier propertyForKey:@"default"];
    uint32_t rgb = 0xFFFFFF;
    if ([value isKindOfClass:NSString.class]) ULPParseHexColor([value UTF8String], &rgb);
    _hexLabel.text = [NSString stringWithFormat:@"#%06X", rgb];
    _swatch.backgroundColor = ULPStyleColor(rgb);
    BOOL enabled = ![specifier propertyForKey:@"enabled"] || [[specifier propertyForKey:@"enabled"] boolValue];
    self.contentView.alpha = enabled ? 1 : .4;
    self.accessibilityValue = _hexLabel.text;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width, height = self.contentView.bounds.size.height;
    self.textLabel.frame = CGRectMake(16, 0, MAX(0, width - 165), height);
    _hexLabel.frame = CGRectMake(MAX(16, width - 142), 0, 90, height);
    _swatch.frame = CGRectMake(width - 40, (height - 24) / 2, 24, 24);
}
@end
