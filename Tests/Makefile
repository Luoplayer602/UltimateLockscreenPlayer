CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -Werror -std=c11

.PHONY: test clean

test: MSH2ProtocolTests LifecycleTests SignalTests VisualConfigTests WaveformTests ProgressClockTests ListPlacementTests PreviewSpectrumTests StyleTests ArtworkRequestTests TrailTests CoverTests
	./MSH2ProtocolTests
	./LifecycleTests
	./SignalTests
	./VisualConfigTests
	./WaveformTests
	./ProgressClockTests
	./ListPlacementTests
	./PreviewSpectrumTests
	./StyleTests
	./ArtworkRequestTests
	./TrailTests
	./CoverTests
	python3 SettingsSchemaTests.py

MSH2ProtocolTests: MSH2ProtocolTests.c ../Audio/MSH2Protocol.c ../Audio/MSH2Protocol.h
	$(CC) $(CFLAGS) MSH2ProtocolTests.c ../Audio/MSH2Protocol.c -o $@

LifecycleTests: LifecycleTests.c ../Playback/ULPLifecycle.c ../Playback/ULPLifecycle.h
	$(CC) $(CFLAGS) LifecycleTests.c ../Playback/ULPLifecycle.c -o $@

SignalTests: SignalTests.c ../Visualization/ULPSignal.c ../Visualization/ULPSignal.h ../Audio/MSH2Protocol.h
	$(CC) $(CFLAGS) SignalTests.c ../Visualization/ULPSignal.c -lm -o $@

VisualConfigTests: VisualConfigTests.c ../Visualization/ULPVisualConfig.c ../Visualization/ULPVisualConfig.h
	$(CC) $(CFLAGS) VisualConfigTests.c ../Visualization/ULPVisualConfig.c -lm -o $@

WaveformTests: WaveformTests.c ../Visualization/ULPWaveform.c ../Visualization/ULPWaveform.h
	$(CC) $(CFLAGS) WaveformTests.c ../Visualization/ULPWaveform.c -lm -o $@

ProgressClockTests: ProgressClockTests.c ../Playback/ULPProgressClock.c ../Playback/ULPProgressClock.h
	$(CC) $(CFLAGS) ProgressClockTests.c ../Playback/ULPProgressClock.c -lm -o $@

ListPlacementTests: ListPlacementTests.c ../Playback/ULPListPlacement.c ../Playback/ULPListPlacement.h
	$(CC) $(CFLAGS) ListPlacementTests.c ../Playback/ULPListPlacement.c -lm -o $@

clean:
	rm -f MSH2ProtocolTests LifecycleTests SignalTests VisualConfigTests WaveformTests ProgressClockTests ListPlacementTests PreviewSpectrumTests StyleTests ArtworkRequestTests TrailTests CoverTests

CoverTests: CoverTests.c ../Visualization/ULPCover.c ../Visualization/ULPCover.h ../Visualization/ULPVisualConfig.c ../Visualization/ULPVisualConfig.h
	$(CC) $(CFLAGS) CoverTests.c ../Visualization/ULPCover.c ../Visualization/ULPVisualConfig.c -lm -o $@

PreviewSpectrumTests: PreviewSpectrumTests.c ../Audio/ULPPreviewSpectrum.c ../Audio/ULPPreviewSpectrum.h
	$(CC) $(CFLAGS) PreviewSpectrumTests.c ../Audio/ULPPreviewSpectrum.c -lm -o $@

StyleTests: StyleTests.c ../Visualization/ULPStyle.c ../Visualization/ULPStyle.h
	$(CC) $(CFLAGS) StyleTests.c ../Visualization/ULPStyle.c -lm -o $@

ArtworkRequestTests: ArtworkRequestTests.c ../Playback/ULPArtworkRequest.c ../Playback/ULPArtworkRequest.h
	$(CC) $(CFLAGS) ArtworkRequestTests.c ../Playback/ULPArtworkRequest.c -lm -o $@

TrailTests: TrailTests.c ../Visualization/ULPTrail.c ../Visualization/ULPTrail.h
	$(CC) $(CFLAGS) TrailTests.c ../Visualization/ULPTrail.c -lm -o $@
