#import "ULPLabeledSliderCell.h"
#import <Preferences/PSSpecifier.h>
#import <math.h>

@implementation ULPLabeledSliderCell {
    UILabel *_settingLabel;
    UILabel *_valueLabel;
    UILabel *_helpLabel;
    UISlider *_slider;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)identifier
                   specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (!self) return nil;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    _settingLabel = [UILabel new];
    _settingLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _settingLabel.textColor = UIColor.labelColor;
    _settingLabel.adjustsFontSizeToFitWidth = YES;
    _settingLabel.minimumScaleFactor = .75;
    _valueLabel = [UILabel new];
    _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    _valueLabel.textColor = UIColor.secondaryLabelColor;
    _valueLabel.textAlignment = NSTextAlignmentRight;
    _slider = [UISlider new];
    _slider.minimumTrackTintColor = UIColor.systemRedColor;
    [_slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    _helpLabel = [UILabel new];
    _helpLabel.font = [UIFont systemFontOfSize:10];
    _helpLabel.textColor = UIColor.secondaryLabelColor;
    _helpLabel.numberOfLines = 2;
    for (UIView *view in @[_settingLabel, _valueLabel, _slider, _helpLabel])
        [self.contentView addSubview:view];
    [self refreshCellContentsWithSpecifier:specifier];
    return self;
}

- (void)updateValueLabel {
    BOOL integer = [[self.specifier propertyForKey:@"ulpInteger"] boolValue];
    _valueLabel.text = [NSString stringWithFormat:integer ? @"%.0f" : @"%.2f", _slider.value];
    _slider.accessibilityValue = _valueLabel.text;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    self.specifier = specifier;
    if (!_slider) return;
    self.textLabel.hidden = YES;
    _settingLabel.text = specifier.name;
    _helpLabel.text = [specifier propertyForKey:@"ulpHelp"];
    _slider.minimumValue = [[specifier propertyForKey:@"min"] floatValue];
    _slider.maximumValue = [[specifier propertyForKey:@"max"] floatValue];
    id value = [specifier performGetter] ?: [specifier propertyForKey:@"default"];
    _slider.value = [value floatValue];
    _slider.enabled = ![specifier propertyForKey:@"enabled"] || [[specifier propertyForKey:@"enabled"] boolValue];
    self.contentView.alpha = _slider.enabled ? 1 : .4;
    _slider.accessibilityLabel = specifier.name;
    [self updateValueLabel];
    [self setNeedsLayout];
}

- (void)sliderChanged:(UISlider *)slider {
    if ([[self.specifier propertyForKey:@"ulpInteger"] boolValue]) slider.value = roundf(slider.value);
    [self.specifier performSetterWithValue:@(slider.value)];
    [self updateValueLabel];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.textLabel.hidden = YES;
    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    _settingLabel.frame = CGRectMake(16, 5, MAX(0, width - 106), 21);
    _valueLabel.frame = CGRectMake(MAX(16, width - 84), 5, 68, 21);
    _slider.frame = CGRectMake(16, 29, MAX(0, width - 32), 28);
    _helpLabel.hidden = !_helpLabel.text.length;
    _helpLabel.frame = CGRectMake(16, 61, MAX(0, width - 32), 30);
}
@end
