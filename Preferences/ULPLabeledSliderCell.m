#import "ULPLabeledSliderCell.h"

#import <Preferences/PSSpecifier.h>

@implementation ULPLabeledSliderCell {
    UILabel *_settingLabel;
    UILabel *_helpLabel;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)identifier
                   specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (!self) return nil;
    _settingLabel = [UILabel new];
    _settingLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _settingLabel.textColor = UIColor.whiteColor;
    _settingLabel.numberOfLines = 1;
    _settingLabel.adjustsFontSizeToFitWidth = YES;
    _settingLabel.minimumScaleFactor = 0.75;
    _settingLabel.text = specifier.name;
    [self.contentView addSubview:_settingLabel];
    _helpLabel = [UILabel new];
    _helpLabel.font = [UIFont systemFontOfSize:11];
    _helpLabel.textColor = UIColor.secondaryLabelColor;
    _helpLabel.numberOfLines = 3;
    _helpLabel.text = [specifier propertyForKey:@"ulpHelp"];
    [self.contentView addSubview:_helpLabel];
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    _settingLabel.text = specifier.name;
    _helpLabel.text = [specifier propertyForKey:@"ulpHelp"];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    _settingLabel.frame = CGRectMake(16, 4, MAX(0, width - 32), 21);
    [self.contentView bringSubviewToFront:_settingLabel];
    _helpLabel.frame = CGRectMake(16, 26, MAX(0, width - 32), 40);
    _helpLabel.hidden = !_helpLabel.text.length;
    if (self.control) {
        CGRect frame = self.control.frame;
        frame.origin.y = MAX(30, CGRectGetHeight(self.contentView.bounds) - 38);
        self.control.frame = frame;
    }
}

@end
