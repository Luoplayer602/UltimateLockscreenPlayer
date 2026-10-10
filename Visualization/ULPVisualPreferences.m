#import "ULPVisualPreferences.h"
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>
#import "ULPStyle.h"

static CFStringRef const ULPDomain = CFSTR("com.luoplayer.ultimatelockscreenplayer");

static NSDictionary *ULPSnapshot(void) {
    CFPreferencesAppSynchronize(ULPDomain);
    CFDictionaryRef raw = CFPreferencesCopyMultiple(NULL, ULPDomain,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    return CFBridgingRelease(raw) ?: @{};
}

static double ULPNumber(NSDictionary *values, NSString *key, double fallback) {
    id value = values[key];
    double number = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
    return isfinite(number) ? number : fallback;
}

static BOOL ULPBool(NSDictionary *values, NSString *key, BOOL fallback) {
    id value = values[key];
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}

static uint8_t ULPByte(NSDictionary *values, NSString *key, uint8_t fallback, uint8_t maximum) {
    return (uint8_t)MAX(0, MIN(maximum, round(ULPNumber(values, key, fallback))));
}

static uint32_t ULPColor(NSDictionary *values, NSString *key, uint32_t fallback) {
    id value = values[key];
    uint32_t rgb = fallback;
    if ([value isKindOfClass:NSString.class]) {
        NSString *hex = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        ULPParseHexColor(hex.UTF8String, &rgb);
    }
    return rgb;
}

static ULPVisualMode ULPSelectedMode(NSDictionary *values) {
    BOOL modern = [values[@"VisualSchemaVersion"] integerValue] >= 1;
    ULPVisualConfig config = ULPVisualConfigDefault();
    config.mode = (ULPVisualMode)ULPByte(values,
        modern ? @"SelectedVisualMode" : @"VisualMode", 0, 255);
    if (!modern) config.preset = (ULPVisualPreset)ULPByte(values, @"VisualPreset", 0, 255);
    return ULPVisualConfigNormalize(config).mode;
}

NSString *ULPVisualPreferenceKey(NSString *key, ULPVisualMode mode) {
    if ([key isEqualToString:@"VisualEnabled"] || [key isEqualToString:@"VisualFPS"])
        return key;
    return [NSString stringWithFormat:@"v1.%s.%@", ULPVisualModeID(mode), key];
}

static NSDictionary *ULPProfile(NSDictionary *values, ULPVisualMode mode) {
    if ([values[@"VisualSchemaVersion"] integerValue] < 1) return values;
    NSMutableDictionary *profile = [NSMutableDictionary dictionary];
    NSString *prefix = [NSString stringWithFormat:@"v1.%s.", ULPVisualModeID(mode)];
    for (NSString *key in values) {
        if ([key hasPrefix:prefix]) profile[[key substringFromIndex:prefix.length]] = values[key];
    }
    for (NSString *key in @[@"VisualEnabled", @"VisualFPS"])
        if (values[key]) profile[key] = values[key];
    return profile;
}

void ULPMigrateVisualPreferences(void) {
    NSDictionary *values = ULPSnapshot();
    if ([values[@"VisualSchemaVersion"] integerValue] >= 1) return;
    ULPVisualMode mode = ULPSelectedMode(values);
    // Leave all old keys intact so installing 0.1.0-49 restores its configuration.
    NSArray *keys = @[@"VisualPoints", @"VisualFirstBand", @"VisualLastBand",
        @"VisualSymmetry", @"VisualOffsetX", @"VisualOffsetY", @"VisualAnimationScale",
        @"VisualScale", @"VisualZoomStrength", @"VisualAutoColor", @"VisualColor",
        @"ZoomFirstBand", @"ZoomLastBand"];
    for (NSString *key in keys) {
        NSString *destination = ULPVisualPreferenceKey(key, mode);
        if (values[key] && !values[destination])
            CFPreferencesSetAppValue((__bridge CFStringRef)destination,
                                     (__bridge CFPropertyListRef)values[key], ULPDomain);
    }
    // Preserve the old frequency ordering while moving it to independent toggles.
    if (ULPVisualIsSpectrum(mode)) {
        NSInteger symmetry = values[@"VisualSymmetry"] ? [values[@"VisualSymmetry"] integerValue] : 1;
        for (NSString *key in @[@"SpectrumMirror", @"SpectrumReverse"])
            CFPreferencesSetAppValue((__bridge CFStringRef)ULPVisualPreferenceKey(key, mode),
                (symmetry & 1) ? kCFBooleanTrue : kCFBooleanFalse, ULPDomain);
        if (symmetry & 2) {
            CFPreferencesSetAppValue((__bridge CFStringRef)ULPVisualPreferenceKey(@"GrowFrom", mode),
                                     (__bridge CFPropertyListRef)@1, ULPDomain);
            CFPreferencesSetAppValue((__bridge CFStringRef)ULPVisualPreferenceKey(@"MirrorVertical", mode),
                                     kCFBooleanTrue, ULPDomain);
        }
    }
    CFPreferencesSetAppValue(CFSTR("SelectedVisualMode"), (__bridge CFPropertyListRef)@(mode), ULPDomain);
    CFPreferencesAppSynchronize(ULPDomain);
    CFPreferencesSetAppValue(CFSTR("VisualSchemaVersion"), (__bridge CFPropertyListRef)@1, ULPDomain);
    CFPreferencesAppSynchronize(ULPDomain);
}

void ULPSelectVisualMode(ULPVisualMode mode) {
    ULPMigrateVisualPreferences();
    mode = ULPVisualConfigDefaultForMode(mode).mode;
    CFPreferencesSetAppValue(CFSTR("SelectedVisualMode"), (__bridge CFPropertyListRef)@(mode), ULPDomain);
    CFPreferencesAppSynchronize(ULPDomain);
}

ULPVisualConfig ULPLoadVisualPreferences(void) {
    NSDictionary *snapshot = ULPSnapshot();
    ULPVisualMode mode = ULPSelectedMode(snapshot);
    NSDictionary *values = ULPProfile(snapshot, mode);
    ULPVisualConfig config = ULPVisualConfigDefaultForMode(mode);
    config.enabled = ULPBool(values, @"VisualEnabled", YES);
    config.points = ULPByte(values, @"VisualPoints", config.points, 128);
    config.framesPerSecond = ULPByte(values, @"VisualFPS", config.framesPerSecond, 60);
    config.firstBand = ULPByte(values, @"VisualFirstBand", config.firstBand, 63);
    config.lastBand = ULPByte(values, @"VisualLastBand", config.lastBand, 63);
    config.zoomFirstBand = ULPByte(values, @"ZoomFirstBand", config.zoomFirstBand, 63);
    config.zoomLastBand = ULPByte(values, @"ZoomLastBand", config.zoomLastBand, 63);
    config.symmetry = (ULPSymmetry)(int)MAX(-1, MIN(4, ULPNumber(values, @"VisualSymmetry", config.symmetry)));
#define NUMBER(field, key) config.field = ULPNumber(values, @key, config.field)
#define BOOLEAN(field, key) config.field = ULPBool(values, @key, config.field)
    NUMBER(offsetX, "VisualOffsetX"); NUMBER(offsetY, "VisualOffsetY");
    NUMBER(animationScale, "VisualAnimationScale"); NUMBER(scale, "VisualScale");
    NUMBER(zoomStrength, "VisualZoomStrength"); BOOLEAN(automaticColor, "VisualAutoColor");
    NUMBER(width, "VisualWidth"); NUMBER(height, "VisualHeight"); NUMBER(rotation, "VisualRotation");
    BOOLEAN(flipX, "VisualFlipX"); BOOLEAN(flipY, "VisualFlipY");
    NUMBER(opacity, "VisualOpacity"); NUMBER(glow, "VisualGlow");
    BOOLEAN(trailEnabled, "TrailEnabled"); NUMBER(trailDuration, "TrailDuration");
    NUMBER(trailOpacity, "TrailOpacity");
    NUMBER(barWidth, "BarWidth"); NUMBER(spacing, "BarSpacing"); NUMBER(barHeight, "BarHeight");
    NUMBER(cornerRadius, "BarCornerRadius"); NUMBER(frequencyRange, "FrequencyRange");
    BOOLEAN(mirror, "SpectrumMirror"); BOOLEAN(reverse, "SpectrumReverse");
    NUMBER(edgeFade, "EdgeFade"); NUMBER(minimumHeight, "MinimumHeight"); NUMBER(dynamics, "Dynamics");
    BOOLEAN(peakCaps, "PeakCaps"); NUMBER(capThickness, "CapThickness");
    NUMBER(dotSize, "DotSize"); NUMBER(unlitOpacity, "UnlitOpacity"); NUMBER(thickness, "Thickness");
    BOOLEAN(fill, "SpectrumFill"); NUMBER(fillOpacity, "FillOpacity"); BOOLEAN(mirrorVertical, "MirrorVertical");
    NUMBER(waveAmplitude, "WaveAmplitude"); NUMBER(waveSmoothing, "WaveSmoothing");
    NUMBER(centreGap, "CentreGap"); BOOLEAN(smoothCurve, "SmoothCurve");
    NUMBER(innerRadius, "InnerRadius"); NUMBER(radialBarLength, "RadialBarLength");
    NUMBER(radialBarThickness, "RadialBarThickness"); NUMBER(rotationSpeed, "RotationSpeed");
    NUMBER(smoothSpectroSize, "SmoothSpectroSize");
    NUMBER(smoothSpectroReactivity, "SmoothSpectroReactivity");
    BOOLEAN(growInward, "GrowInward"); BOOLEAN(roundedCaps, "RoundedCaps");
    BOOLEAN(showInnerRing, "ShowInnerRing"); NUMBER(ringOpacity, "RingOpacity");
    BOOLEAN(hideVisualizerButPeakCaps, "HideVisualizerButPeakCaps");
    config.growFrom = ULPByte(values, @"GrowFrom", config.growFrom, 255);
    config.rows = ULPByte(values, @"Rows", config.rows, 32);
    config.radialSymmetry = ULPByte(values, @"RadialSymmetry", config.radialSymmetry, 12);
    config.peakCapsType = ULPByte(values, @"PeakCapsType", config.peakCapsType, 1);
    config.colorMode = ULPByte(values, @"ColourMode", config.automaticColor ? 2 : 0, 255);
    config.color1 = ULPColor(values, @"VisualColor", config.color1);
    config.color2 = ULPColor(values, @"VisualColor2", config.color2);
    NUMBER(gradientAngle, "GradientAngle");
    config.backgroundMode = ULPByte(values, @"BackgroundMode", 0, 255);
    config.backgroundColor1 = ULPColor(values, @"BackgroundColor1", config.backgroundColor1);
    config.backgroundColor2 = ULPColor(values, @"BackgroundColor2", config.backgroundColor2);
    BOOLEAN(artworkBackground, "ArtworkBackground");
    config.artworkBackgroundType = ULPByte(values, @"ArtworkBackgroundType", 2, 255);
    config.coverMode = (ULPCoverMode)ULPByte(values, @"CoverMode", config.coverMode, 255);
    NUMBER(coverSize, "CoverSize"); NUMBER(coverX, "CoverX"); NUMBER(coverY, "CoverY");
    NUMBER(coverOpacity, "CoverOpacity"); NUMBER(coverOutlineThickness, "CoverOutlineThickness");
    NUMBER(coverOutlineOpacity, "CoverOutlineOpacity"); NUMBER(coverGlow, "CoverGlow");
    NUMBER(coverSpin, "CoverSpin");
    config.coverOutlineColor = ULPColor(values, @"CoverOutlineColor", config.coverOutlineColor);
#undef NUMBER
#undef BOOLEAN
    return ULPVisualConfigNormalize(config);
}

UIColor *ULPLoadVisualManualColor(void) {
    NSDictionary *snapshot = ULPSnapshot();
    NSDictionary *profile = ULPProfile(snapshot, ULPSelectedMode(snapshot));
    id value = profile[@"VisualColor"];
    NSString *hex = [value isKindOfClass:NSString.class] ?
        [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"#FFFFFF";
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    unsigned rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    if (!(hex.length == 6 && [scanner scanHexInt:&rgb] && scanner.isAtEnd)) rgb = 0xFFFFFF;
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0
                          green:((rgb >> 8) & 255) / 255.0
                           blue:(rgb & 255) / 255.0 alpha:1];
}
