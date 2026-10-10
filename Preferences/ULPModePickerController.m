#import "ULPModePickerController.h"
#import "../Visualization/ULPVisualPreferences.h"

NSString *ULPModeTitle(ULPVisualMode mode) {
    switch (mode) {
        case ULPVisualModeBar: return @"Bar";
        case ULPVisualModeEqualizer: return @"Equalizer";
        case ULPVisualModeLine: return @"Line";
        case ULPVisualModeDotMatrix: return @"Dot";
        case ULPVisualModeWave: return @"Waveform";
        case ULPVisualModeMirror: return @"Mirror";
        case ULPVisualModeSiri: return @"Siri";
        case ULPVisualModeRadial: return @"Spectro";
        case ULPVisualModeCircularWave: return @"Circular waveform";
        case ULPVisualModeSmoothSpectro: return @"Smooth spectro";
        case ULPVisualModeDot: return @"Dotted orbit";
        default: return @"Circle classic";
    }
}

@implementation ULPModePickerController {
    NSArray<NSArray<NSNumber *> *> *_modes;
    ULPVisualMode _selected;
}

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Modes";
    _modes = @[@[@(ULPVisualModeBar), @(ULPVisualModeEqualizer), @(ULPVisualModeLine), @(ULPVisualModeDotMatrix)],
               @[@(ULPVisualModeWave), @(ULPVisualModeMirror), @(ULPVisualModeSiri)],
               @[@(ULPVisualModeCircle), @(ULPVisualModeRadial), @(ULPVisualModeCircularWave),
                 @(ULPVisualModeSmoothSpectro), @(ULPVisualModeDot)]];
    _selected = ULPLoadVisualPreferences().mode;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return _modes.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _modes[section].count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"SPECTRUM", @"WAVEFORM", @"CIRCULAR"][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? @"Mỗi mode giữ cài đặt riêng. Chọn mode rồi quay lại để tinh chỉnh và xem trước." : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"mode"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"mode"];
    ULPVisualMode mode = (ULPVisualMode)[_modes[indexPath.section][indexPath.row] intValue];
    cell.textLabel.text = ULPModeTitle(mode);
    cell.detailTextLabel.text = mode == ULPVisualModeEqualizer ? @"Ma trận ô vuông" :
        mode == ULPVisualModeDotMatrix ? @"Ma trận chấm tròn" :
        mode == ULPVisualModeDot ? @"Vòng chấm của bản trước" : nil;
    cell.accessoryType = mode == _selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    ULPSelectVisualMode((ULPVisualMode)[_modes[indexPath.section][indexPath.row] intValue]);
    [self.navigationController popViewControllerAnimated:YES];
}
@end
