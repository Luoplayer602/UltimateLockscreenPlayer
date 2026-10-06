#include "ServerInternal.h"

#include <sched.h>
#include <unistd.h>

namespace MSHFServer {

CaptureEngineState gCapture{};

namespace {

Candidate *FindCandidate(AudioUnit unit) {
    for (Candidate &candidate : gCapture.candidates) {
        if (candidate.used && candidate.unit == unit) {
            return &candidate;
        }
    }
    return nullptr;
}

bool IsEligibleUnit(AudioUnit unit) {
    if (!unit) {
        return false;
    }
    AudioComponent component = AudioComponentInstanceGetComponent(unit);
    AudioComponentDescription description{};
    return component &&
           AudioComponentGetDescription(component, &description) == noErr &&
           description.componentSubType ==
               kAudioUnitSubType_MultiChannelMixer;
}

bool DescribeSource(Candidate *candidate, SourceDescription *description) {
    if (!candidate || !candidate->used || !candidate->initialized ||
        !description) {
        return false;
    }

    AudioComponent component = AudioComponentInstanceGetComponent(candidate->unit);
    AudioComponentDescription componentDescription{};
    if (!component ||
        AudioComponentGetDescription(component, &componentDescription) != noErr ||
        componentDescription.componentSubType !=
            kAudioUnitSubType_MultiChannelMixer) {
        return false;
    }

    AudioStreamBasicDescription format{};
    UInt32 formatSize = sizeof(format);
    if (AudioUnitGetProperty(candidate->unit, kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Output, 0, &format,
                             &formatSize) != noErr ||
        formatSize != sizeof(format)) {
        return false;
    }
    if (format.mFormatID != kAudioFormatLinearPCM ||
        (format.mFormatFlags & kAudioFormatFlagIsFloat) == 0 ||
        format.mBitsPerChannel != 32 || format.mSampleRate <= 0 ||
        !std::isfinite(format.mSampleRate)) {
        return false;
    }

    CaptureLayout layout = CaptureLayout::Unsupported;
    bool nonInterleaved =
        (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    // A single channel has the same one-buffer layout with or without the
    // non-interleaved flag. iPhone 6s/iOS 15.8.5 reports this flag for mono.
    if (format.mChannelsPerFrame == 1 &&
        format.mBytesPerFrame == sizeof(float)) {
        layout = CaptureLayout::MonoFloat32;
    } else if (!nonInterleaved && format.mChannelsPerFrame == 2 &&
               format.mBytesPerFrame == sizeof(float) * 2) {
        layout = CaptureLayout::InterleavedStereoFloat32;
    } else if (nonInterleaved && format.mChannelsPerFrame == 2 &&
               format.mBytesPerFrame == sizeof(float)) {
        layout = CaptureLayout::NonInterleavedStereoFloat32;
    }
    if (layout == CaptureLayout::Unsupported) {
        return false;
    }

    UInt32 maximumFrames = 0;
    UInt32 maximumFramesSize = sizeof(maximumFrames);
    if (AudioUnitGetProperty(candidate->unit,
                             kAudioUnitProperty_MaximumFramesPerSlice,
                             kAudioUnitScope_Global, 0, &maximumFrames,
                             &maximumFramesSize) != noErr ||
        maximumFramesSize != sizeof(maximumFrames) || maximumFrames == 0) {
        return false;
    }
    if (maximumFrames > kMaximumQuantum) {
        return false;
    }

    description->unit = candidate->unit;
    description->candidateGeneration = candidate->generation;
    description->bus = 0;
    description->format = format;
    description->layout = layout;
    description->maximumFrames = maximumFrames;
    description->valid = true;
    return true;
}

bool DescriptionsEqual(const SourceDescription &left,
                       const SourceDescription &right) {
    if (left.valid != right.valid) {
        return false;
    }
    if (!left.valid) {
        return true;
    }
    CaptureSource comparable{};
    comparable.unit = left.unit;
    comparable.candidateGeneration = left.candidateGeneration;
    comparable.bus = left.bus;
    comparable.format = left.format;
    comparable.layout = left.layout;
    comparable.maximumFrames = left.maximumFrames;
    return SourceMatchesDescription(&comparable, right);
}

uint64_t NextSourceGeneration() {
    gCapture.sourceGeneration =
        (gCapture.sourceGeneration + 1) & MSHFActiveSourceToken::kGenerationMask;
    if (gCapture.sourceGeneration == 0) {
        gCapture.sourceGeneration = 1;
    }
    return gCapture.sourceGeneration;
}

SourceDrainHandle CurrentDrainHandle() {
    if (!gCapture.drainingSource) {
        return {};
    }
    return {gCapture.drainingSource, gCapture.drainingSourceGeneration};
}

uint32_t SourceSlotIndex(const CaptureSource *source) {
    return static_cast<uint32_t>(source - gCapture.sourceSlots);
}

void QuarantineSource(SourceDrainHandle handle) {
    if (!handle.source || handle.sourceGeneration == 0 ||
        handle.source < gCapture.sourceSlots ||
        handle.source >= gCapture.sourceSlots + kSourceSlotCount ||
        handle.source->sourceGeneration.load(std::memory_order_acquire) !=
            handle.sourceGeneration) {
        return;
    }
    const uint32_t slot = SourceSlotIndex(handle.source);
    if (!gCapture.sourceQuarantined[slot] ||
        gCapture.quarantinedGeneration[slot] != handle.sourceGeneration) {
        gCapture.sourceQuarantined[slot] = true;
        gCapture.quarantinedGeneration[slot] = handle.sourceGeneration;
        ++gCapture.sourceQuarantineCount;
    }
}

void ReapQuarantine(SourceDrainHandle handle) {
    if (!handle.source || handle.source < gCapture.sourceSlots ||
        handle.source >= gCapture.sourceSlots + kSourceSlotCount) {
        return;
    }
    const uint32_t slot = SourceSlotIndex(handle.source);
    if (gCapture.sourceQuarantined[slot] &&
        gCapture.quarantinedGeneration[slot] == handle.sourceGeneration &&
        (handle.source->gate.load(std::memory_order_acquire) &
         kGateCountMask) == 0) {
        gCapture.sourceQuarantined[slot] = false;
        gCapture.quarantinedGeneration[slot] = 0;
    }
}

CaptureSource *FindReusableSourceSlot(uint32_t *slotIndex) {
    for (uint32_t offset = 0; offset < kSourceSlotCount; ++offset) {
        const uint32_t candidateSlot =
            (gCapture.nextSourceSlot + offset) % kSourceSlotCount;
        CaptureSource *source = &gCapture.sourceSlots[candidateSlot];
        ReapQuarantine({source,
                        source->sourceGeneration.load(std::memory_order_acquire)});
        if (!gCapture.sourceQuarantined[candidateSlot] &&
            (source->gate.load(std::memory_order_acquire) &
             kGateCountMask) == 0) {
            *slotIndex = candidateSlot;
            return source;
        }
    }
    return nullptr;
}

void ResetCaptureState() {
    gCapture.sampleWrite.store(0, std::memory_order_relaxed);
    gCapture.sampleRead.store(0, std::memory_order_relaxed);
    gCapture.descriptorWrite.store(0, std::memory_order_relaxed);
    gCapture.descriptorRead.store(0, std::memory_order_relaxed);
    gCapture.captureFaults.store(0, std::memory_order_relaxed);
    // Source replacement is a PCM discontinuity, but not necessarily a
    // playback stop. Preserve an already-qualified activity latch so a short
    // AudioUnit teardown/recreation does not emit a false Silence frame. The
    // preserved last-audio timestamp still expires through the normal
    // activity gate when no replacement audio arrives.
    ResetDSPState(true);
}

bool PendingSourceStillValid() {
    if (!gCapture.pendingSource.valid) {
        return false;
    }
    Candidate *candidate = FindCandidate(gCapture.pendingSource.unit);
    return candidate && candidate->initialized &&
           candidate->generation == gCapture.pendingSource.candidateGeneration;
}

void ContinueTransition();

void ScheduleTransitionPoll(uint64_t delayNs) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 static_cast<int64_t>(delayNs)),
                   gRuntime.controlQueue, ^{
                     ContinueTransition();
                   });
}

/// Completes source publication after the previous gate reaches zero.
///
/// Threading: Serial control queue only.
/// Synchronization: Publishes a fully initialized immutable source slot with
/// one release-store to the active token. The render thread never waits.
void ContinueTransition() {
    if (!gCapture.transitionScheduled) {
        return;
    }
    if (gCapture.drainingSource &&
        (gCapture.drainingSource->gate.load(std::memory_order_acquire) &
         kGateCountMask) != 0) {
        const uint64_t elapsedNs =
            MonotonicNanoseconds() - gCapture.transitionStartNs;
        if (MSHFLifecyclePolicy::ShouldQuarantine(elapsedNs)) {
            QuarantineSource(CurrentDrainHandle());
            ScheduleTransitionPoll(MSHFLifecyclePolicy::kQuarantinePollNs);
        } else {
            ScheduleTransitionPoll(
                MSHFLifecyclePolicy::NextDelay(&gCapture.transitionBackoff));
        }
        return;
    }

    ReapQuarantine(CurrentDrainHandle());

    uint32_t sourceSlot = 0;
    CaptureSource *source = nullptr;
    if (PendingSourceStillValid()) {
        source = FindReusableSourceSlot(&sourceSlot);
        if (!source) {
            ScheduleTransitionPoll(MSHFLifecyclePolicy::kQuarantinePollNs);
            return;
        }
    }

    ++gCapture.streamEpoch;
    ResetCaptureState();

    gCapture.drainingSource = nullptr;
    gCapture.drainingSourceGeneration = 0;
    gCapture.transitionScheduled = false;
    gCapture.transitionStartNs = 0;
    gCapture.transitionBackoff = {};
    if (!source) {
        memset(&gCapture.pendingSource, 0, sizeof(gCapture.pendingSource));
        return;
    }

    gCapture.nextSourceSlot = (sourceSlot + 1) % kSourceSlotCount;
    uint64_t sourceGeneration = NextSourceGeneration();
    source->unit = gCapture.pendingSource.unit;
    source->candidateGeneration = gCapture.pendingSource.candidateGeneration;
    source->streamEpoch = gCapture.streamEpoch;
    source->bus = gCapture.pendingSource.bus;
    source->format = gCapture.pendingSource.format;
    source->layout = gCapture.pendingSource.layout;
    source->maximumFrames = gCapture.pendingSource.maximumFrames;
    source->sourceGeneration.store(sourceGeneration,
                                   std::memory_order_release);
    source->gate.store(0, std::memory_order_release);
    gCapture.activeSourceToken.store(
        MSHFActiveSourceToken::Encode(sourceSlot, sourceGeneration),
        std::memory_order_release);
    gCapture.captureEnabled.store(ClientCountOnControlQueue() > 0,
                                  std::memory_order_release);
    memset(&gCapture.pendingSource, 0, sizeof(gCapture.pendingSource));
}

void SelectCandidate(Candidate *candidate) {
    SourceDescription description{};
    if (DescribeBestSource(candidate, &description)) {
        BeginTransition(&description);
    } else {
        BeginTransition(nullptr);
    }
}

bool ValidateBuffers(const CaptureSource *source, UInt32 frames,
                     const AudioBufferList *buffers) {
    if (!source || !buffers || frames == 0 || frames > kMaximumQuantum ||
        frames > source->maximumFrames) {
        return false;
    }

    switch (source->layout) {
    case CaptureLayout::MonoFloat32:
        return buffers->mNumberBuffers == 1 &&
               buffers->mBuffers[0].mNumberChannels == 1 &&
               buffers->mBuffers[0].mData &&
               buffers->mBuffers[0].mDataByteSize >= frames * sizeof(float);
    case CaptureLayout::InterleavedStereoFloat32:
        return buffers->mNumberBuffers == 1 &&
               buffers->mBuffers[0].mNumberChannels == 2 &&
               buffers->mBuffers[0].mData &&
               buffers->mBuffers[0].mDataByteSize >=
                   frames * sizeof(float) * 2;
    case CaptureLayout::NonInterleavedStereoFloat32:
        return buffers->mNumberBuffers == 2 &&
               buffers->mBuffers[0].mNumberChannels == 1 &&
               buffers->mBuffers[1].mNumberChannels == 1 &&
               buffers->mBuffers[0].mData && buffers->mBuffers[1].mData &&
               buffers->mBuffers[0].mDataByteSize >= frames * sizeof(float) &&
               buffers->mBuffers[1].mDataByteSize >= frames * sizeof(float);
    default:
        return false;
    }
}

void WriteCapturedSegment(const CaptureSource *source,
                          const AudioBufferList *buffers,
                          uint32_t sourceOffset, float *destination,
                          uint32_t frameCount, bool silence) {
    if (silence) {
        vDSP_vclr(destination, 1, frameCount);
        return;
    }
    if (source->layout == CaptureLayout::MonoFloat32) {
        const float *mono =
            static_cast<const float *>(buffers->mBuffers[0].mData);
        memcpy(destination, mono + sourceOffset, frameCount * sizeof(float));
        return;
    }

    const float half = 0.5f;
    if (source->layout == CaptureLayout::InterleavedStereoFloat32) {
        const float *stereo =
            static_cast<const float *>(buffers->mBuffers[0].mData) +
            sourceOffset * 2;
        vDSP_vasm(stereo, 2, stereo + 1, 2, &half, destination, 1,
                  frameCount);
        return;
    }

    const float *left =
        static_cast<const float *>(buffers->mBuffers[0].mData) + sourceOffset;
    const float *right =
        static_cast<const float *>(buffers->mBuffers[1].mData) + sourceOffset;
    vDSP_vasm(left, 1, right, 1, &half, destination, 1, frameCount);
}

} // namespace

/// Admits one callback into a source slot unless teardown has closed its gate.
/// This operation is lock-free and never waits.
bool GateEnter(CaptureSource *source) {
    uint64_t value = source->gate.load(std::memory_order_acquire);
    while ((value & kGateClosed) == 0) {
        if ((value & kGateCountMask) == kGateCountMask) {
            return false;
        }
        if (source->gate.compare_exchange_weak(
                value, value + 1, std::memory_order_acquire,
                std::memory_order_relaxed)) {
            return true;
        }
    }
    return false;
}

/// Releases one render callback previously admitted by `GateEnter`.
void GateExit(CaptureSource *source) {
    source->gate.fetch_sub(1, std::memory_order_release);
}

/// Prevents new callbacks from entering while preserving the in-flight count.
void CloseGate(CaptureSource *source) {
    if (source) {
        source->gate.fetch_or(kGateClosed, std::memory_order_acq_rel);
    }
}

CaptureSource *SourceForToken(uint64_t token, uint64_t *generation) {
    uint32_t slotIndex = 0;
    uint64_t decodedGeneration = 0;
    if (!MSHFActiveSourceToken::Decode(token, kSourceSlotCount, &slotIndex,
                                       &decodedGeneration)) {
        return nullptr;
    }
    if (generation) {
        *generation = decodedGeneration;
    }
    return &gCapture.sourceSlots[slotIndex];
}

CaptureSource *ActiveSourceOnControlQueue() {
    uint64_t generation = 0;
    CaptureSource *source = SourceForToken(
        gCapture.activeSourceToken.load(std::memory_order_acquire), &generation);
    return source && source->sourceGeneration.load(std::memory_order_acquire) ==
                         generation
               ? source
               : nullptr;
}

bool WaitForSourceDrain(SourceDrainHandle handle) {
    if (!handle.source || handle.sourceGeneration == 0) {
        return true;
    }
    uint32_t yields = 0;
    const uint64_t startNs = MonotonicNanoseconds();
    MSHFLifecyclePolicy::Backoff backoff{};
    while (handle.source->sourceGeneration.load(std::memory_order_acquire) ==
               handle.sourceGeneration &&
           (handle.source->gate.load(std::memory_order_acquire) &
            kGateCountMask) != 0) {
        if (yields++ < MSHFLifecyclePolicy::kFastYieldCount) {
            sched_yield();
        } else {
            const uint64_t elapsedNs = MonotonicNanoseconds() - startNs;
            if (MSHFLifecyclePolicy::ShouldQuarantine(elapsedNs)) {
                RunControlSync(^{
                  QuarantineSource(handle);
                  ++gCapture.sourceDrainTimeoutCount;
                });
                return false;
            }
            const uint64_t delayNs =
                MSHFLifecyclePolicy::NextDelay(&backoff);
            usleep(static_cast<useconds_t>(
                std::max<uint64_t>(delayNs / 1000, 1)));
        }
    }
    return true;
}

Candidate *NewestInitializedCandidate() {
    Candidate *newest = nullptr;
    for (Candidate &candidate : gCapture.candidates) {
        if (candidate.used && candidate.initialized &&
            (!newest || candidate.order > newest->order)) {
            newest = &candidate;
        }
    }
    return newest;
}

bool DescribeBestSource(Candidate *preferred,
                        SourceDescription *description) {
    if (!description) {
        return false;
    }
    if (preferred && DescribeSource(preferred, description)) {
        return true;
    }

    Candidate *best = nullptr;
    SourceDescription bestDescription{};
    for (Candidate &candidate : gCapture.candidates) {
        if (&candidate == preferred || !candidate.used ||
            !candidate.initialized || (best && candidate.order <= best->order)) {
            continue;
        }
        SourceDescription candidateDescription{};
        if (DescribeSource(&candidate, &candidateDescription)) {
            best = &candidate;
            bestDescription = candidateDescription;
        }
    }
    if (!best) {
        return false;
    }
    *description = bestDescription;
    return true;
}

bool SourceMatchesDescription(const CaptureSource *source,
                              const SourceDescription &description) {
    if (!source || !description.valid || source->unit != description.unit ||
        source->candidateGeneration != description.candidateGeneration ||
        source->bus != description.bus || source->layout != description.layout ||
        source->maximumFrames != description.maximumFrames) {
        return false;
    }
    const AudioStreamBasicDescription &left = source->format;
    const AudioStreamBasicDescription &right = description.format;
    return left.mSampleRate == right.mSampleRate &&
           left.mFormatID == right.mFormatID &&
           left.mFormatFlags == right.mFormatFlags &&
           left.mBytesPerPacket == right.mBytesPerPacket &&
           left.mFramesPerPacket == right.mFramesPerPacket &&
           left.mBytesPerFrame == right.mBytesPerFrame &&
           left.mChannelsPerFrame == right.mChannelsPerFrame &&
           left.mBitsPerChannel == right.mBitsPerChannel;
}

/// Begins or retargets a source transition on the serial control queue.
/// The render thread is disabled before publication is cleared; quiescence is
/// observed asynchronously and never by waiting on the render thread.
SourceDrainHandle BeginTransition(const SourceDescription *description) {
    CaptureSource *active = ActiveSourceOnControlQueue();
    if (description) {
        if (!gCapture.transitionScheduled &&
            SourceMatchesDescription(active, *description)) {
            gCapture.captureEnabled.store(ClientCountOnControlQueue() > 0,
                                  std::memory_order_release);
            return CurrentDrainHandle();
        }
        if (gCapture.transitionScheduled &&
            DescriptionsEqual(gCapture.pendingSource, *description)) {
            return CurrentDrainHandle();
        }
    } else if ((!gCapture.transitionScheduled && !active) ||
               (gCapture.transitionScheduled && !gCapture.pendingSource.valid)) {
        gCapture.captureEnabled.store(false, std::memory_order_release);
        return CurrentDrainHandle();
    }

    if (description) {
        gCapture.pendingSource = *description;
    } else {
        memset(&gCapture.pendingSource, 0, sizeof(gCapture.pendingSource));
    }
    gCapture.captureEnabled.store(false, std::memory_order_release);
    uint64_t activeToken =
        gCapture.activeSourceToken.exchange(0, std::memory_order_acq_rel);
    uint64_t activeGeneration = 0;
    CaptureSource *publishedSource =
        SourceForToken(activeToken, &activeGeneration);
    SourceDrainHandle drainHandle{publishedSource, activeGeneration};
    if (publishedSource) {
        CloseGate(publishedSource);
        gCapture.drainingSource = publishedSource;
        gCapture.drainingSourceGeneration = activeGeneration;
    } else if (gCapture.transitionScheduled) {
        drainHandle = CurrentDrainHandle();
    }

    if (!gCapture.transitionScheduled) {
        gCapture.transitionScheduled = true;
        gCapture.transitionStartNs = MonotonicNanoseconds();
        gCapture.transitionBackoff = {};
        ContinueTransition();
    }
    return drainHandle;
}

bool RegisterCandidate(AudioUnit unit, bool initialized) {
    if (!IsEligibleUnit(unit)) {
        return false;
    }
    Candidate *candidate = FindCandidate(unit);
    if (!candidate) {
        for (Candidate &slot : gCapture.candidates) {
            if (!slot.used) {
                candidate = &slot;
                memset(candidate, 0, sizeof(*candidate));
                candidate->unit = unit;
                candidate->used = true;
                candidate->generation = ++gCapture.candidateGeneration;
                break;
            }
        }
    }
    if (!candidate) {
        ++gCapture.candidateSaturationCount;
        return false;
    }

    bool becameInitialized = initialized && !candidate->initialized;
    if (!becameInitialized) {
        return true;
    }
    candidate->initialized = true;
    candidate->order = ++gCapture.candidateOrder;
    SourceDescription description{};
    if (DescribeSource(candidate, &description)) {
        SelectCandidate(candidate);
    }
    return true;
}

void RequestRefreshForPropertyChange(AudioUnit unit) {
    Candidate *candidate = FindCandidate(unit);
    if (!candidate || !candidate->initialized) {
        return;
    }
    CaptureSource *active = ActiveSourceOnControlQueue();
    bool activeCandidate = active && active->unit == unit &&
                           active->candidateGeneration ==
                               candidate->generation;
    bool pendingCandidate = gCapture.pendingSource.valid &&
                            gCapture.pendingSource.unit == unit &&
                            gCapture.pendingSource.candidateGeneration ==
                                candidate->generation;
    if (activeCandidate || pendingCandidate || !active) {
        gCapture.refreshRequested.store(true, std::memory_order_release);
    }
}

CandidateRollback DeactivateCandidate(AudioUnit unit) {
    Candidate *candidate = FindCandidate(unit);
    if (!candidate) {
        return {};
    }
    CandidateRollback rollback{candidate, *candidate, {}};
    SourceDrainHandle existingDrain{};
    if (gCapture.drainingSource && gCapture.drainingSource->unit == unit) {
        existingDrain = CurrentDrainHandle();
    } else {
        for (uint32_t slot = 0; slot < kSourceSlotCount; ++slot) {
            CaptureSource *source = &gCapture.sourceSlots[slot];
            if (gCapture.sourceQuarantined[slot] && source->unit == unit) {
                existingDrain = {source,
                                 gCapture.quarantinedGeneration[slot]};
                break;
            }
        }
    }
    CaptureSource *active = ActiveSourceOnControlQueue();
    bool wasActive = active && active->unit == unit;
    candidate->initialized = false;
    candidate->generation = ++gCapture.candidateGeneration;

    if (wasActive || (gCapture.pendingSource.valid && gCapture.pendingSource.unit == unit)) {
        Candidate *replacement = NewestInitializedCandidate();
        SourceDescription description{};
        SourceDrainHandle newDrain =
            DescribeBestSource(replacement, &description)
                ? BeginTransition(&description)
                : BeginTransition(nullptr);
        rollback.drainHandle = newDrain.source ? newDrain : existingDrain;
        return rollback;
    }
    rollback.drainHandle = existingDrain;
    return rollback;
}

void RestoreCandidate(const CandidateRollback &rollback) {
    if (!rollback.candidate) {
        return;
    }
    *rollback.candidate = rollback.previous;
    if (rollback.drainHandle.source &&
        rollback.drainHandle.source->unit == rollback.previous.unit) {
        SelectCandidate(rollback.candidate);
    } else {
        RefreshActiveSource();
    }
}

void RestoreCandidateWithoutPublication(const CandidateRollback &rollback) {
    if (rollback.candidate) {
        *rollback.candidate = rollback.previous;
    }
}

void CommitCandidateDeactivation(const CandidateRollback &rollback,
                                 bool dispose) {
    if (!rollback.candidate || !dispose) {
        return;
    }
    uint64_t generation = rollback.candidate->generation;
    memset(rollback.candidate, 0, sizeof(*rollback.candidate));
    rollback.candidate->generation = generation;
}

void RefreshActiveSource() {
    CaptureSource *active = ActiveSourceOnControlQueue();
    Candidate *candidate = active ? FindCandidate(active->unit)
                                  : NewestInitializedCandidate();
    SourceDescription description{};
    if (DescribeBestSource(candidate, &description)) {
        if (SourceMatchesDescription(active, description) ||
            (gCapture.transitionScheduled &&
             DescriptionsEqual(gCapture.pendingSource, description))) {
            return;
        }
        BeginTransition(&description);
    } else if (active || gCapture.transitionScheduled || gCapture.pendingSource.valid) {
        BeginTransition(nullptr);
    }
}

/// Copies one completed render quantum into the capture rings.
///
/// Threading: Called from an arbitrary AudioUnit real-time render thread.
/// Real-time constraints: Must not allocate, block, dispatch, log, query the
/// AudioUnit, touch Objective-C objects, or perform socket/FFT work.
/// Synchronization: The descriptor release-store publishes all sample writes.
/// Failure behavior: Drops the complete quantum and marks a discontinuity;
/// partial quanta are never published.
void CaptureRenderedAudio(CaptureSource *source,
                          AudioUnitRenderActionFlags actionFlags,
                          UInt32 frames, const AudioBufferList *buffers) {
    if (!ValidateBuffers(source, frames, buffers)) {
        gCapture.captureFaults.fetch_or(CaptureFaultInvalidBuffer,
                                std::memory_order_release);
        gCapture.refreshRequested.store(true, std::memory_order_release);
        return;
    }

    uint64_t descriptorWrite =
        gCapture.descriptorWrite.load(std::memory_order_relaxed);
    uint64_t descriptorRead =
        gCapture.descriptorRead.load(std::memory_order_acquire);
    uint64_t sampleWrite = gCapture.sampleWrite.load(std::memory_order_relaxed);
    uint64_t sampleRead = gCapture.sampleRead.load(std::memory_order_acquire);
    if (descriptorWrite - descriptorRead >= kDescriptorCapacity ||
        sampleWrite - sampleRead + frames > kRingCapacity) {
        gCapture.captureFaults.fetch_or(CaptureFaultRingOverrun,
                                std::memory_order_release);
        return;
    }

    bool silence =
        (actionFlags & kAudioUnitRenderAction_OutputIsSilence) != 0;
    uint32_t ringOffset = (uint32_t)(sampleWrite % kRingCapacity);
    uint32_t firstCount = std::min(frames, kRingCapacity - ringOffset);
    WriteCapturedSegment(source, buffers, 0, gCapture.sampleRing + ringOffset,
                         firstCount, silence);
    if (firstCount < frames) {
        WriteCapturedSegment(source, buffers, firstCount, gCapture.sampleRing,
                             frames - firstCount, silence);
    }

    QuantumDescriptor &descriptor =
        gCapture.descriptorRing[descriptorWrite % kDescriptorCapacity];
    descriptor.streamEpoch = source->streamEpoch;
    descriptor.sampleStart = sampleWrite;
    descriptor.frameCount = frames;
    descriptor.flags = silence ? QuantumFlagSilence : 0;
    gCapture.sampleWrite.store(sampleWrite + frames, std::memory_order_relaxed);
    gCapture.descriptorWrite.store(descriptorWrite + 1, std::memory_order_release);
}

/// Drains complete descriptors on the serial control queue and feeds the
/// rolling analyzer/activity gate. Faults flush pending PCM while preserving
/// the gate's latched state and breaking incomplete qualification evidence.
void DrainAudioRing(uint64_t now) {
    uint32_t captureFaults =
        gCapture.captureFaults.exchange(0, std::memory_order_acq_rel);
    if (captureFaults != 0) {
        uint64_t descriptorEnd =
            gCapture.descriptorWrite.load(std::memory_order_acquire);
        uint64_t sampleEnd = gCapture.sampleRead.load(std::memory_order_relaxed);
        if (descriptorEnd > 0) {
            const QuantumDescriptor &last =
                gCapture.descriptorRing[(descriptorEnd - 1) % kDescriptorCapacity];
            sampleEnd = last.sampleStart + last.frameCount;
        }
        gCapture.descriptorRead.store(descriptorEnd, std::memory_order_release);
        gCapture.sampleRead.store(sampleEnd, std::memory_order_release);
        gAnalyzer.rollingCount = 0;
        gAnalyzer.rollingWrite = 0;
        gAnalyzer.activityAccumulator.Reset();
        gAnalyzer.activityGate.BreakContinuity();
        gAnalyzer.lastAnalysisNs = 0;
        gAnalyzer.dspDiscontinuity = true;
        if (gAnalyzer.lastAudioNs) {
            gAnalyzer.activityGate.ObserveCaptureAge(now - gAnalyzer.lastAudioNs);
        }
        return;
    }

    CaptureSource *source = ActiveSourceOnControlQueue();
    double sampleRate = source ? source->format.mSampleRate : 0;
    uint64_t read = gCapture.descriptorRead.load(std::memory_order_relaxed);
    uint64_t write = gCapture.descriptorWrite.load(std::memory_order_acquire);
    bool received = false;
    while (read < write) {
        const QuantumDescriptor &descriptor =
            gCapture.descriptorRing[read % kDescriptorCapacity];
        if (descriptor.streamEpoch != gCapture.streamEpoch ||
            descriptor.frameCount > kMaximumQuantum) {
            gAnalyzer.activityAccumulator.Reset();
            gAnalyzer.activityGate.BreakContinuity();
            gAnalyzer.dspDiscontinuity = true;
        } else {
            bool silence = (descriptor.flags & QuantumFlagSilence) != 0;
            for (uint32_t index = 0; index < descriptor.frameCount; ++index) {
                float sample = AppendRollingSample(
                    silence ? 0.0f
                            : gCapture.sampleRing[(descriptor.sampleStart + index) %
                                          kRingCapacity]);
                MSHFAudioActivity::Observation observation;
                if (gAnalyzer.activityAccumulator.Append(sample, sampleRate,
                                                &observation)) {
                    gAnalyzer.activityGate.Observe(observation);
                }
            }
            received = true;
        }
        gCapture.sampleRead.store(descriptor.sampleStart + descriptor.frameCount,
                          std::memory_order_release);
        ++read;
    }
    gCapture.descriptorRead.store(read, std::memory_order_release);
    if (received) {
        gAnalyzer.lastAudioNs = now;
    } else if (gAnalyzer.lastAudioNs) {
        gAnalyzer.activityGate.ObserveCaptureAge(now - gAnalyzer.lastAudioNs);
    }
}

} // namespace MSHFServer
