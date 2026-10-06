#include "ServerInternal.h"

#include <stdlib.h>
#include <substrate.h>
#include <unistd.h>

namespace MSHFServer {

RuntimeState gRuntime{};

namespace {

void *kControlQueueIdentity = &kControlQueueIdentity;

OSStatus (*gOriginalAudioUnitRender)(AudioUnit, AudioUnitRenderActionFlags *,
                                     const AudioTimeStamp *, UInt32, UInt32,
                                     AudioBufferList *);
OSStatus (*gOriginalAudioUnitInitialize)(AudioUnit);
OSStatus (*gOriginalAudioUnitUninitialize)(AudioUnit);
OSStatus (*gOriginalAudioUnitSetProperty)(AudioUnit, AudioUnitPropertyID,
                                          AudioUnitScope, AudioUnitElement,
                                          const void *, UInt32);
OSStatus (*gOriginalAudioComponentInstanceNew)(AudioComponent,
                                               AudioComponentInstance *);
OSStatus (*gOriginalAudioComponentInstanceDispose)(AudioComponentInstance);

/// Calls the original renderer first, then forwards only the currently
/// published source generation into the lock-free capture engine.
OSStatus HookedAudioUnitRender(AudioUnit unit,
                               AudioUnitRenderActionFlags *actionFlags,
                               const AudioTimeStamp *timestamp, UInt32 bus,
                               UInt32 frames, AudioBufferList *buffers) {
    OSStatus status = gOriginalAudioUnitRender(unit, actionFlags, timestamp, bus,
                                               frames, buffers);
    if (status != noErr || !gCapture.captureEnabled.load(std::memory_order_acquire)) {
        return status;
    }

    uint64_t activeToken =
        gCapture.activeSourceToken.load(std::memory_order_acquire);
    uint64_t sourceGeneration = 0;
    CaptureSource *source = SourceForToken(activeToken, &sourceGeneration);
    if (!source) {
        return status;
    }
    if (!GateEnter(source)) {
        return status;
    }
    if (gCapture.activeSourceToken.load(std::memory_order_acquire) != activeToken ||
        source->sourceGeneration.load(std::memory_order_acquire) !=
            sourceGeneration ||
        !gCapture.captureEnabled.load(std::memory_order_acquire)) {
        GateExit(source);
        return status;
    }
    if (source->unit != unit || source->bus != bus) {
        GateExit(source);
        return status;
    }
    if (gCapture.writerBusy.test_and_set(std::memory_order_acquire)) {
        gCapture.captureFaults.fetch_or(CaptureFaultWriterBusy,
                                std::memory_order_release);
        GateExit(source);
        return status;
    }

    AudioUnitRenderActionFlags flags = actionFlags ? *actionFlags : 0;
    CaptureRenderedAudio(source, flags, frames, buffers);
    gCapture.writerBusy.clear(std::memory_order_release);
    GateExit(source);
    return status;
}

OSStatus HookedAudioComponentInstanceNew(AudioComponent component,
                                         AudioComponentInstance *instance) {
    OSStatus status = gOriginalAudioComponentInstanceNew(component, instance);
    if (status == noErr && instance && *instance) {
        AudioUnit unit = (AudioUnit)*instance;
        RunControlSync(^{
          RegisterCandidate(unit, false);
        });
    }
    return status;
}

OSStatus HookedAudioUnitInitialize(AudioUnit unit) {
    OSStatus status = gOriginalAudioUnitInitialize(unit);
    if (status == noErr && unit) {
        RunControlSync(^{
          RegisterCandidate(unit, true);
        });
    }
    return status;
}

OSStatus HookedAudioUnitUninitialize(AudioUnit unit) {
    __block CandidateRollback rollback{};
    if (unit) {
        RunControlSync(^{
          rollback = DeactivateCandidate(unit);
        });
        if (!WaitForSourceDrain(rollback.drainHandle)) {
            // A wedged render callback owns the source storage. Keep the slot
            // quarantined and refuse destructive AudioUnit lifecycle work;
            // a later caller may retry after the gate count reaches zero.
            RunControlSync(^{
              RestoreCandidateWithoutPublication(rollback);
            });
            return kAudioUnitErr_CannotDoInCurrentContext;
        }
    }
    OSStatus status = gOriginalAudioUnitUninitialize(unit);
    if (rollback.candidate) {
        RunControlSync(^{
          if (status != noErr) {
              RestoreCandidate(rollback);
          } else {
              CommitCandidateDeactivation(rollback, false);
          }
        });
    }
    return status;
}

OSStatus HookedAudioComponentInstanceDispose(AudioComponentInstance instance) {
    AudioUnit unit = (AudioUnit)instance;
    __block CandidateRollback rollback{};
    if (unit) {
        RunControlSync(^{
          rollback = DeactivateCandidate(unit);
        });
        if (!WaitForSourceDrain(rollback.drainHandle)) {
            RunControlSync(^{
              RestoreCandidateWithoutPublication(rollback);
            });
            return kAudioUnitErr_CannotDoInCurrentContext;
        }
    }
    OSStatus status = gOriginalAudioComponentInstanceDispose(instance);
    if (rollback.candidate) {
        RunControlSync(^{
          if (status != noErr) {
              RestoreCandidate(rollback);
          } else {
              CommitCandidateDeactivation(rollback, true);
          }
        });
    }
    return status;
}

bool PropertyAffectsCapturedFormat(AudioUnitPropertyID property,
                                   AudioUnitScope scope,
                                   AudioUnitElement element) {
    return element == 0 &&
           ((property == kAudioUnitProperty_StreamFormat &&
             scope == kAudioUnitScope_Output) ||
            (property == kAudioUnitProperty_MaximumFramesPerSlice &&
             scope == kAudioUnitScope_Global));
}

OSStatus HookedAudioUnitSetProperty(AudioUnit unit, AudioUnitPropertyID property,
                                    AudioUnitScope scope,
                                    AudioUnitElement element,
                                    const void *data, UInt32 dataSize) {
    OSStatus status = gOriginalAudioUnitSetProperty(unit, property, scope,
                                                    element, data, dataSize);
    if (status == noErr && unit &&
        PropertyAffectsCapturedFormat(property, scope, element)) {
        dispatch_async(gRuntime.controlQueue, ^{
          RequestRefreshForPropertyChange(unit);
        });
    }
    return status;
}

void InstallHooks() {
    MSHookFunction((void *)AudioUnitRender, (void *)&HookedAudioUnitRender,
                   (void **)&gOriginalAudioUnitRender);
    MSHookFunction((void *)AudioUnitInitialize,
                   (void *)&HookedAudioUnitInitialize,
                   (void **)&gOriginalAudioUnitInitialize);
    MSHookFunction((void *)AudioUnitUninitialize,
                   (void *)&HookedAudioUnitUninitialize,
                   (void **)&gOriginalAudioUnitUninitialize);
    MSHookFunction((void *)AudioUnitSetProperty,
                   (void *)&HookedAudioUnitSetProperty,
                   (void **)&gOriginalAudioUnitSetProperty);
    MSHookFunction((void *)AudioComponentInstanceNew,
                   (void *)&HookedAudioComponentInstanceNew,
                   (void **)&gOriginalAudioComponentInstanceNew);
    MSHookFunction((void *)AudioComponentInstanceDispose,
                   (void *)&HookedAudioComponentInstanceDispose,
                   (void **)&gOriginalAudioComponentInstanceDispose);
}

} // namespace

uint64_t MonotonicNanoseconds() {
    uint64_t ticks = mach_continuous_time();
    __uint128_t scaled = (__uint128_t)ticks * gRuntime.timebase.numer;
    return (uint64_t)(scaled / gRuntime.timebase.denom);
}

bool IsControlQueue() {
    return dispatch_get_specific(gRuntime.controlQueueKey) == gRuntime.controlQueueKey;
}

void RunControlSync(dispatch_block_t block) {
    if (IsControlQueue()) {
        block();
    } else {
        dispatch_sync(gRuntime.controlQueue, block);
    }
}

__attribute__((constructor)) static void AudioSnapshotServerInitialize() {
    if (mach_timebase_info(&gRuntime.timebase) != KERN_SUCCESS ||
        gRuntime.timebase.denom == 0) {
        return;
    }
    arc4random_buf(&gRuntime.serverInstanceID, sizeof(gRuntime.serverInstanceID));
    if (gRuntime.serverInstanceID == 0) {
        gRuntime.serverInstanceID = 1;
    }

    gRuntime.controlQueue = dispatch_queue_create(
        "com.ryannair05.audiosnapshotserver2.control", DISPATCH_QUEUE_SERIAL);
    if (!gRuntime.controlQueue) {
        return;
    }
    gRuntime.controlQueueKey = kControlQueueIdentity;
    dispatch_queue_set_specific(gRuntime.controlQueue, gRuntime.controlQueueKey,
                                gRuntime.controlQueueKey, nullptr);
    if (!ConfigureInfrastructure()) {
#if !OS_OBJECT_USE_OBJC
        dispatch_release(gRuntime.controlQueue);
#endif
        gRuntime.controlQueue = nullptr;
        gRuntime.controlQueueKey = nullptr;
        return;
    }

    InstallHooks();
}

__attribute__((destructor)) static void AudioSnapshotServerDeinitialize() {
    gCapture.captureEnabled.store(false, std::memory_order_release);
    uint64_t activeToken =
        gCapture.activeSourceToken.exchange(0, std::memory_order_acq_rel);
    CaptureSource *source = SourceForToken(activeToken);
    CloseGate(source);
    if (gServer.analysisTimer) {
        dispatch_source_cancel(gServer.analysisTimer);
    } else if (gAnalyzer.fftSetup) {
        // A configured timer owns normal FFT teardown through its cancel
        // handler. This fallback is only for partial startup.
        vDSP_destroy_fftsetup(gAnalyzer.fftSetup);
        gAnalyzer.fftSetup = nullptr;
    }
    if (gServer.socketSource) {
        dispatch_source_cancel(gServer.socketSource);
    } else if (gServer.socketDescriptor >= 0) {
        close(gServer.socketDescriptor);
        gServer.socketDescriptor = -1;
    }
}

} // namespace MSHFServer
