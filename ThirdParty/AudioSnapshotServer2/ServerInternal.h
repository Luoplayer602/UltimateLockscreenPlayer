#ifndef MSHF_SERVER_INTERNAL_H
#define MSHF_SERVER_INTERNAL_H

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>

#include <Accelerate/Accelerate.h>
#include <AudioToolbox/AudioToolbox.h>
#include <dispatch/dispatch.h>
#include <mach/mach_time.h>
#include <netinet/in.h>

#include "ActiveSourceToken.h"
#include "AudioActivityGate.h"
#include "FeatureDSP.h"
#include "FeaturePacing.h"
#include "LifecyclePolicy.h"
#include "MSHFProtocol.h"
#include "RequestPolicy.h"

namespace MSHFServer {

constexpr uint32_t kCandidateCapacity = 16;
constexpr uint32_t kSourceSlotCount = 2;
constexpr uint32_t kRingCapacity = 16384;
constexpr uint32_t kDescriptorCapacity = 256;
constexpr uint32_t kMaximumQuantum = 4096;
constexpr uint32_t kAnalysisFrames = 2048;
constexpr uint32_t kFFTLog2 = 11;
constexpr uint32_t kFeatureCount = MSHF_PROTOCOL_MAX_FEATURE_VALUES;
constexpr uint32_t kFFTComplexCount = kAnalysisFrames / 2;
constexpr uint32_t kFFTBinCount = (kAnalysisFrames / 2) + 1;
// Intersections between two ordered interval partitions are bounded by the
// combined partition sizes. One spare entry keeps the proof conservative at
// shared floating-point boundaries.
constexpr uint32_t kMaximumBandWeights = kFFTBinCount + kFeatureCount + 1;
constexpr uint32_t kClientCapacity = 32;
constexpr uint32_t kMaximumDatagramsPerRead = 64;
constexpr uint16_t kMinimumAnalysisRate = 24;
constexpr uint64_t kGateClosed = UINT64_C(1) << 63;
constexpr uint64_t kGateCountMask = ~kGateClosed;
constexpr uint64_t kClientTimeoutNs = UINT64_C(15) * NSEC_PER_SEC;
constexpr uint64_t kSilenceHeartbeatNs = UINT64_C(2) * NSEC_PER_SEC;

static_assert(std::atomic<bool>::is_always_lock_free);
static_assert(std::atomic<uint32_t>::is_always_lock_free);
static_assert(std::atomic<uint64_t>::is_always_lock_free);
static_assert(kSourceSlotCount <= MSHFActiveSourceToken::kSlotMask + 1,
              "Source slot count exceeds active-token encoding");
static_assert((UINT32_C(1) << kFFTLog2) == kAnalysisFrames,
              "FFT order must match the analysis frame count");

enum class CaptureLayout : uint8_t {
    Unsupported = 0,
    MonoFloat32,
    InterleavedStereoFloat32,
    NonInterleavedStereoFloat32,
};

struct Candidate {
    AudioUnit unit;
    uint64_t generation;
    uint64_t order;
    bool used;
    bool initialized;
};

struct SourceDescription {
    AudioUnit unit;
    uint64_t candidateGeneration;
    uint32_t bus;
    AudioStreamBasicDescription format;
    CaptureLayout layout;
    uint32_t maximumFrames;
    bool valid;
};

struct CaptureSource {
    std::atomic<uint64_t> sourceGeneration;
    AudioUnit unit;
    uint64_t candidateGeneration;
    uint64_t streamEpoch;
    uint32_t bus;
    AudioStreamBasicDescription format;
    CaptureLayout layout;
    uint32_t maximumFrames;
    std::atomic<uint64_t> gate;
};

struct SourceDrainHandle {
    CaptureSource *source;
    uint64_t sourceGeneration;
};

struct CandidateRollback {
    Candidate *candidate;
    Candidate previous;
    SourceDrainHandle drainHandle;
};

struct QuantumDescriptor {
    uint64_t streamEpoch;
    uint64_t sampleStart;
    uint32_t frameCount;
    uint32_t flags;
};

enum QuantumFlags : uint32_t {
    QuantumFlagSilence = 1u << 0,
};

enum CaptureFault : uint32_t {
    CaptureFaultRingOverrun = 1u << 0,
    CaptureFaultWriterBusy = 1u << 1,
    CaptureFaultInvalidBuffer = 1u << 2,
    CaptureFaultWarmResume = 1u << 3,
};

struct Client {
    bool used;
    sockaddr_in address;
    uint64_t sessionID;
    uint64_t lastSeenNs;
    MSHFFeaturePacer featurePacer;
    uint64_t lastRequestSequence;
    uint32_t featureMask;
    uint16_t featureRate;
    uint16_t graceSeconds;
};

struct FeatureFrame {
    uint64_t streamEpoch;
    uint32_t status;
    float sampleRate;
    float rms;
    float peak;
    float waveform[kFeatureCount];
    float spectrum[kFeatureCount];
};

struct BandWeight {
    uint16_t bin;
    float weight;
};

struct RuntimeState {
    dispatch_queue_t controlQueue = nullptr;
    void *controlQueueKey = nullptr;
    uint64_t serverInstanceID = 0;
    mach_timebase_info_data_t timebase{};
};

struct CaptureEngineState {
    Candidate candidates[kCandidateCapacity]{};
    uint64_t candidateOrder = 0;
    uint64_t candidateGeneration = 0;
    CaptureSource sourceSlots[kSourceSlotCount]{};
    uint32_t nextSourceSlot = 0;
    uint64_t sourceGeneration = 0;
    std::atomic<uint64_t> activeSourceToken{0};
    std::atomic<bool> captureEnabled{false};
    std::atomic_flag writerBusy = ATOMIC_FLAG_INIT;
    std::atomic<bool> refreshRequested{false};
    CaptureSource *drainingSource = nullptr;
    uint64_t drainingSourceGeneration = 0;
    SourceDescription pendingSource{};
    bool transitionScheduled = false;
    uint64_t transitionStartNs = 0;
    MSHFLifecyclePolicy::Backoff transitionBackoff{};
    bool sourceQuarantined[kSourceSlotCount]{};
    uint64_t quarantinedGeneration[kSourceSlotCount]{};
    uint64_t candidateSaturationCount = 0;
    uint64_t sourceDrainTimeoutCount = 0;
    uint64_t sourceQuarantineCount = 0;
    uint64_t streamEpoch = 0;
    alignas(64) float sampleRing[kRingCapacity]{};
    QuantumDescriptor descriptorRing[kDescriptorCapacity]{};
    std::atomic<uint64_t> sampleWrite{0};
    std::atomic<uint64_t> sampleRead{0};
    std::atomic<uint64_t> descriptorWrite{0};
    std::atomic<uint64_t> descriptorRead{0};
    std::atomic<uint32_t> captureFaults{0};
};

struct FeatureAnalyzerState {
    float rollingSamples[kAnalysisFrames]{};
    uint32_t rollingWrite = 0;
    uint32_t rollingCount = 0;
    uint64_t lastAudioNs = 0;
    MSHFAudioActivity::EnergyAccumulator activityAccumulator{};
    MSHFAudioActivity::Gate activityGate{};
    bool dspDiscontinuity = false;
    bool nonFiniteInputPending = false;
    float rawWindow[kAnalysisFrames]{};
    float fftInput[kAnalysisFrames]{};
    float fftSplitReal[kFFTComplexCount]{};
    float fftSplitImag[kFFTComplexCount]{};
    float fftPower[kFFTBinCount]{};
    float hannWindow[kAnalysisFrames]{};
    BandWeight bandWeights[kMaximumBandWeights]{};
    uint16_t bandWeightOffsets[kFeatureCount + 1]{};
    float bandWeightSums[kFeatureCount]{};
    float bandDecibels[kFeatureCount]{};
    float spectrumTargets[kFeatureCount]{};
    float smoothedSpectrum[kFeatureCount]{};
    float smoothedRMS = 0;
    float smoothedPeak = 0;
    float bandSampleRate = 0;
    float windowPowerGain = 1;
    uint64_t lastAnalysisNs = 0;
    FFTSetup fftSetup = nullptr;
};

struct FeatureServerState {
    dispatch_source_t socketSource = nullptr;
    dispatch_source_t analysisTimer = nullptr;
    int socketDescriptor = -1;
    uint64_t datagramSequence = 0;
    Client clients[kClientCapacity]{};
    uint32_t requestedFeatureMask = 0;
    uint16_t drainRate = kMinimumAnalysisRate;
    uint16_t productionRate = 5;
    MSHFFeaturePacer productionPacer{};
    MSHFSilencePacer silencePacer{};
    uint64_t idleGeneration = 0;
    uint64_t clientSaturationCount = 0;
    uint64_t socketReadErrorCount = 0;
    int lastSocketError = 0;
};

extern RuntimeState gRuntime;
extern CaptureEngineState gCapture;
extern FeatureAnalyzerState gAnalyzer;
extern FeatureServerState gServer;

uint64_t MonotonicNanoseconds();
bool IsControlQueue();
void RunControlSync(dispatch_block_t block);

CaptureSource *ActiveSourceOnControlQueue();
CaptureSource *SourceForToken(uint64_t token,
                              uint64_t *generation = nullptr);
bool GateEnter(CaptureSource *source);
void GateExit(CaptureSource *source);
void CloseGate(CaptureSource *source);
bool WaitForSourceDrain(SourceDrainHandle handle);
bool RegisterCandidate(AudioUnit unit, bool initialized);
void RequestRefreshForPropertyChange(AudioUnit unit);
CandidateRollback DeactivateCandidate(AudioUnit unit);
void RestoreCandidate(const CandidateRollback &rollback);
void RestoreCandidateWithoutPublication(const CandidateRollback &rollback);
void CommitCandidateDeactivation(const CandidateRollback &rollback,
                                 bool dispose);
void CaptureRenderedAudio(CaptureSource *source,
                          AudioUnitRenderActionFlags actionFlags,
                          UInt32 frames, const AudioBufferList *buffers);
Candidate *NewestInitializedCandidate();
bool DescribeBestSource(Candidate *preferred, SourceDescription *description);
bool SourceMatchesDescription(const CaptureSource *source,
                              const SourceDescription &description);
SourceDrainHandle BeginTransition(const SourceDescription *description);
void RefreshActiveSource();
void DrainAudioRing(uint64_t now);
void ResetDSPState(bool preserveQualifiedActivity);
void ResetSpectrumSmoothing();
float AppendRollingSample(float sample);
bool ProduceFeatureFrame(uint64_t now, FeatureFrame *frame);
bool ConfigureDSP();
bool ConfigureInfrastructure();
uint32_t ClientCountOnControlQueue();

} // namespace MSHFServer

#endif
