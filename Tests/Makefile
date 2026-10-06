CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -Werror -std=c11

.PHONY: test clean

test: MSH2ProtocolTests LifecycleTests SignalTests
	./MSH2ProtocolTests
	./LifecycleTests
	./SignalTests

MSH2ProtocolTests: MSH2ProtocolTests.c ../Audio/MSH2Protocol.c ../Audio/MSH2Protocol.h
	$(CC) $(CFLAGS) MSH2ProtocolTests.c ../Audio/MSH2Protocol.c -o $@

LifecycleTests: LifecycleTests.c ../Playback/ULPLifecycle.c ../Playback/ULPLifecycle.h
	$(CC) $(CFLAGS) LifecycleTests.c ../Playback/ULPLifecycle.c -o $@

SignalTests: SignalTests.c ../Visualization/ULPSignal.c ../Visualization/ULPSignal.h ../Audio/MSH2Protocol.h
	$(CC) $(CFLAGS) SignalTests.c ../Visualization/ULPSignal.c -lm -o $@

clean:
	rm -f MSH2ProtocolTests LifecycleTests SignalTests
