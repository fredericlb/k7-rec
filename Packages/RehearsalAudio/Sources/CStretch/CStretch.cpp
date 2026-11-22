// The C face of Signalsmith Stretch: buffers made at creation, the shift applied at the next block, a pass-through
// at 0 semitones that resets the shifter so a later shift starts clean.
#include "CStretch.h"
#include "vendor/signalsmith-stretch.h"
#include <atomic>
#include <vector>

struct CStretch {
    signalsmith::stretch::SignalsmithStretch<float> stretch;
    std::vector<std::vector<float>> input;
    std::vector<float *> inputs;
    std::vector<float *> outputs;
    int channels;
    int maxFrames;
    double sampleRate;
    std::atomic<float> wanted{0};
    float applied = 0;
};

extern "C" CStretch *cstretch_create(int channels, double sampleRate, int maxFrames) {
    auto *s = new CStretch();
    s->channels = channels;
    s->maxFrames = maxFrames;
    s->sampleRate = sampleRate;
    s->stretch.presetDefault(channels, float(sampleRate));
    // Formants stay where they were, so a shifted voice keeps its timbre; 200 Hz is a voice's middle register.
    s->stretch.setFormantFactor(1, true);
    s->stretch.setFormantBase(float(200 / sampleRate));
    s->input.assign(channels, std::vector<float>(maxFrames, 0));
    for (auto &c : s->input) s->inputs.push_back(c.data());
    s->outputs.assign(channels, nullptr);
    return s;
}

extern "C" void cstretch_destroy(CStretch *s) { delete s; }

extern "C" void cstretch_set_semitones(CStretch *s, float semitones) { s->wanted.store(semitones); }

extern "C" int cstretch_latency(const CStretch *s) { return s->stretch.inputLatency() + s->stretch.outputLatency(); }

extern "C" void cstretch_process(CStretch *s, float *const *channels, int frames) {
    float wanted = s->wanted.load();
    if (wanted != s->applied) {
        if (s->applied == 0) s->stretch.reset();
        s->stretch.setTransposeSemitones(wanted);
        s->applied = wanted;
    }
    if (s->applied == 0) return;
    for (int done = 0; done < frames;) {
        int n = std::min(frames - done, s->maxFrames);
        for (int c = 0; c < s->channels; ++c) {
            std::copy(channels[c] + done, channels[c] + done + n, s->inputs[c]);
            s->outputs[c] = channels[c] + done;
        }
        s->stretch.process(s->inputs, n, s->outputs, n);
        done += n;
    }
}
