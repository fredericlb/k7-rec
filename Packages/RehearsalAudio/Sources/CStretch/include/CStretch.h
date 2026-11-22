// A C face for the Signalsmith Stretch pitch shifter, so Swift calls it without C++ interop (docs/audio.md).
// One instance per audio stream; process runs in place on the render thread and never allocates.
#pragma once
#ifdef __cplusplus
extern "C" {
#endif

typedef struct CStretch CStretch;

/// A shifter for `channels` channels at `sampleRate`, taking at most `maxFrames` frames per call.
CStretch *cstretch_create(int channels, double sampleRate, int maxFrames);
void cstretch_destroy(CStretch *s);
/// The shift in semitones, the tempo kept; read by the next process call, from any thread.
void cstretch_set_semitones(CStretch *s, float semitones);
/// Frames the output lags its input while shifting.
int cstretch_latency(const CStretch *s);
/// Shifts `frames` frames of non-interleaved channels in place; at 0 semitones the audio passes untouched.
void cstretch_process(CStretch *s, float *const *channels, int frames);

#ifdef __cplusplus
}
#endif
