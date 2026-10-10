#import "ULPStylePickerController.h"
#import <Preferences/PSSpecifier.h>
#import "../UI/ULPStyleColors.h"

@interface ULPStylePickerController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@end

@implementation ULPStylePickerController {
    UITableView *_choices;
    NSArray *_values;
    NSArray *_titles;
    UIView *_swatch;
    UITextField *_hex;
    NSArray<UISlider *> *_channels;
    NSArray<UILabel *> *_numbers;
    uint32_t _rgb;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.specifier.name;
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    if ([[self.specifier propertyForKey:@"ulpColorPicker"] boolValue]) {
        [self buildColourEditor];
    } else {
        _values = [self.specifier propertyForKey:@"ulpChoiceValues"] ?: @[];
        _titles = [self.specifier propertyForKey:@"ulpChoiceTitles"] ?: @[];
        _choices = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
        _choices.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _choices.dataSource = self;
        _choices.delegate = self;
        [self.view addSubview:_choices];
    }
}

- (id)currentValue {
    return [self.specifier performGetter] ?: [self.specifier propertyForKey:@"default"];
}

- (void)saveValue:(id)value {
    // The source controller owns persistence, dependencies and preview refresh.
    [self.specifier performSetterWithValue:value];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MIN(_values.count, _titles.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"choice"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"choice"];
    cell.textLabel.text = _titles[indexPath.row];
    cell.textLabel.numberOfLines = 0;
    cell.accessoryType = [[self currentValue] isEqual:_values[indexPath.row]] ?
        UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self saveValue:_values[indexPath.row]];
    [tableView reloadData];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)buildColourEditor {
    _rgb = 0xFFFFFF;
    id value = [self currentValue];
    if ([value isKindOfClass:NSString.class]) ULPParseHexColor([value UTF8String], &_rgb);
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:scroll];
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 20;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:24],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-32],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-24],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-48]
    ]];
    _swatch = [UIView new];
    _swatch.layer.cornerRadius = 20;
    _swatch.layer.borderWidth = 1;
    _swatch.layer.borderColor = UIColor.separatorColor.CGColor;
    [_swatch.heightAnchor constraintEqualToConstant:100].active = YES;
    [stack addArrangedSubview:_swatch];
    _hex = [UITextField new];
    _hex.borderStyle = UITextBorderStyleRoundedRect;
    _hex.font = [UIFont monospacedSystemFontOfSize:20 weight:UIFontWeightMedium];
    _hex.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    _hex.autocorrectionType = UITextAutocorrectionTypeNo;
    _hex.returnKeyType = UIReturnKeyDone;
    _hex.delegate = self;
    _hex.accessibilityLabel = @"Hex colour";
    [_hex addTarget:self action:@selector(hexFinished) forControlEvents:UIControlEventEditingDidEnd];
    [stack addArrangedSubview:_hex];
    NSMutableArray *sliders = [NSMutableArray array], *numbers = [NSMutableArray array];
    NSArray *names = @[@"Red", @"Green", @"Blue"];
    NSArray *colors = @[UIColor.systemRedColor, UIColor.systemGreenColor, UIColor.systemBlueColor];
    for (NSInteger i = 0; i < 3; ++i) {
        UILabel *label = [UILabel new];
        label.textColor = UIColor.labelColor;
        [stack addArrangedSubview:label];
        [numbers addObject:label];
        UISlider *slider = [UISlider new];
        slider.minimumValue = 0; slider.maximumValue = 255;
        slider.tag = i;
        slider.minimumTrackTintColor = colors[i];
        slider.accessibilityLabel = names[i];
        [slider addTarget:self action:@selector(channelChanged:) forControlEvents:UIControlEventValueChanged];
        [sliders addObject:slider];
        [stack addArrangedSubview:slider];
    }
    _channels = sliders; _numbers = numbers;
    UIStackView *palette = [UIStackView new];
    palette.distribution = UIStackViewDistributionFillEqually;
    palette.spacing = 8;
    for (NSNumber *color in @[@0xFFFFFF, @0x19191F, @0xFF80B5, @0xFF453A, @0x64D2FF, @0x30D158]) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = color.unsignedIntValue;
        button.backgroundColor = ULPStyleColor((uint32_t)button.tag);
        button.layer.cornerRadius = 10;
        button.layer.borderWidth = 1;
        button.layer.borderColor = UIColor.separatorColor.CGColor;
        button.accessibilityLabel = [NSString stringWithFormat:@"#%06X", (uint32_t)button.tag];
        [button.heightAnchor constraintEqualToConstant:40].active = YES;
        [button addTarget:self action:@selector(paletteSelected:) forControlEvents:UIControlEventTouchUpInside];
        [palette addArrangedSubview:button];
    }
    [stack addArrangedSubview:palette];
    UILabel *footer = [UILabel new];
    footer.text = @"Màu được lưu ngay. Quay lại để xem preview; nhấn Apply để áp dụng trên màn hình khóa.";
    footer.textColor = UIColor.secondaryLabelColor;
    footer.font = [UIFont systemFontOfSize:14];
    footer.numberOfLines = 0;
    [stack addArrangedSubview:footer];
    [self updateColourControls];
}

- (void)updateColourControls {
    _swatch.backgroundColor = ULPStyleColor(_rgb);
    _hex.text = [NSString stringWithFormat:@"#%06X", _rgb];
    NSArray *names = @[@"Red", @"Green", @"Blue"];
    for (NSUInteger i = 0; i < 3; ++i) {
        unsigned value = (_rgb >> ((2 - i) * 8)) & 255;
        _channels[i].value = value;
        _numbers[i].text = [NSString stringWithFormat:@"%@ · %u", names[i], value];
    }
}

- (void)channelChanged:(UISlider *)slider {
    unsigned shift = (2 - (unsigned)slider.tag) * 8;
    _rgb = (_rgb & ~(255u << shift)) | ((uint32_t)lroundf(slider.value) << shift);
    [self updateColourControls];
    [self saveValue:_hex.text];
}

- (void)paletteSelected:(UIButton *)button {
    _rgb = (uint32_t)button.tag;
    [self updateColourControls];
    [self saveValue:_hex.text];
}

- (void)hexFinished {
    NSString *value = [_hex.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (ULPParseHexColor(value.UTF8String, &_rgb)) {
        [self updateColourControls];
        [self saveValue:_hex.text];
    } else {
        [self updateColourControls];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Mã màu không hợp lệ"
            message:@"Nhập 6 ký tự hex, ví dụ #FF80B5." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [self.view endEditing:YES];
    [super viewWillDisappear:animated];
}
@end
