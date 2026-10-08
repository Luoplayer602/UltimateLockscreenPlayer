#import "ULPSettingsListController.h"

#import <spawn.h>

extern char **environ;

@implementation ULPSettingsListController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Apply"
                style:UIBarButtonItemStyleDone
               target:self
               action:@selector(applySettings)];
}

- (void)applySettings {
    // sbreload is provided by the jailbreak and can be run from Settings.
    const char *paths[] = {"/var/jb/usr/bin/sbreload", "/usr/bin/sbreload"};
    int error = -1;
    for (unsigned i = 0; i < sizeof(paths) / sizeof(paths[0]); ++i) {
        pid_t process = 0;
        char *const arguments[] = {(char *)paths[i], NULL};
        error = posix_spawn(&process, paths[i], NULL, NULL, arguments, environ);
        if (error == 0) return;
    }
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Không thể Respring"
                        message:@"Không tìm thấy sbreload. Có thể Respring bằng trình quản lý jailbreak để áp dụng thay đổi."
                 preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
