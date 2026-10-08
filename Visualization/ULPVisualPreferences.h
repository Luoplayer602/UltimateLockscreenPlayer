#import <UIKit/UIKit.h>

#import "ULPVisualConfig.h"

#ifdef __cplusplus
extern "C" {
#endif

ULPVisualConfig ULPLoadVisualPreferences(void);
UIColor *ULPLoadVisualManualColor(void);
NSString *ULPVisualPreferenceKey(NSString *key, ULPVisualMode mode);
void ULPMigrateVisualPreferences(void);
void ULPSelectVisualMode(ULPVisualMode mode);

#ifdef __cplusplus
}
#endif
