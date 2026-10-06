#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <arpa/inet.h>
#include <AudioToolbox/AudioToolbox.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static void logStatus(const char *message) {
    int fd = open("/var/mobile/Library/Logs/ULPServerProbe.log",
                  O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (fd >= 0) {
        (void)write(fd, message, strlen(message));
        (void)write(fd, "\n", 1);
        close(fd);
    }
    int socketDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (socketDescriptor < 0) return;
    struct sockaddr_in listener = {};
    listener.sin_family = AF_INET;
    listener.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    listener.sin_port = htons(44334);
    (void)sendto(socketDescriptor, message, strlen(message), 0,
                 (const struct sockaddr *)&listener, sizeof(listener));
    close(socketDescriptor);
}

static void readStatus(void) {
    using RunControlSync = void (*)(dispatch_block_t);
    using ClientCount = unsigned (*)(void);
    using SourceGetter = void *(*)(void);
    auto run = (RunControlSync)dlsym(RTLD_DEFAULT,
        "_ZN10MSHFServer14RunControlSyncEU13block_pointerFvvE");
    auto count = (ClientCount)dlsym(RTLD_DEFAULT,
        "_ZN10MSHFServer25ClientCountOnControlQueueEv");
    auto active = (SourceGetter)dlsym(RTLD_DEFAULT,
        "_ZN10MSHFServer26ActiveSourceOnControlQueueEv");
    auto candidate = (SourceGetter)dlsym(RTLD_DEFAULT,
        "_ZN10MSHFServer26NewestInitializedCandidateEv");
    if (!run || !count || !active || !candidate) {
        logStatus("AudioSnapshotServer2 diagnostic symbols unavailable");
        return;
    }
    __block unsigned clients = 0;
    __block bool hasActive = false;
    __block bool hasCandidate = false;
    __block uint32_t subtype = 0;
    __block OSStatus componentStatus = -1;
    __block OSStatus formatStatus = -1;
    __block OSStatus maximumStatus = -1;
    __block AudioStreamBasicDescription format = {};
    __block uint32_t maximumFrames = 0;
    run(^{
        clients = count();
        hasActive = active() != nullptr;
        void *candidatePointer = candidate();
        hasCandidate = candidatePointer != nullptr;
        if (!candidatePointer) return;
        AudioUnit unit = *(AudioUnit *)candidatePointer;
        AudioComponent component = AudioComponentInstanceGetComponent(unit);
        AudioComponentDescription componentDescription = {};
        if (component) componentStatus = AudioComponentGetDescription(component, &componentDescription);
        if (componentStatus == noErr) subtype = componentDescription.componentSubType;
        UInt32 formatSize = sizeof(format);
        formatStatus = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat,
                                            kAudioUnitScope_Output, 0, &format, &formatSize);
        UInt32 maximumSize = sizeof(maximumFrames);
        maximumStatus = AudioUnitGetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice,
                                             kAudioUnitScope_Global, 0,
                                             &maximumFrames, &maximumSize);
    });
    char line[400];
    snprintf(line, sizeof(line),
             "clients=%u active=%u candidate=%u subtype=%08x componentErr=%d formatErr=%d format=%08x flags=%08x rate=%.0f channels=%u bits=%u bytesFrame=%u maxErr=%d maxFrames=%u",
             clients, hasActive, hasCandidate, subtype, componentStatus,
             formatStatus, format.mFormatID, format.mFormatFlags, format.mSampleRate,
             format.mChannelsPerFrame, format.mBitsPerChannel, format.mBytesPerFrame,
             maximumStatus, maximumFrames);
    logStatus(line);
}

static void scheduleRead(unsigned remaining) {
    if (!remaining) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        readStatus();
        scheduleRead(remaining - 1);
    });
}

__attribute__((constructor)) static void ULPServerProbeInitialize(void) {
    logStatus("ULPServerProbe loaded");
    scheduleRead(24);
}
