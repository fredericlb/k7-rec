# Audio

`Packages/RehearsalAudio` records a take, reads its envelope, finds its moments, plays it back and
clicks a tempo. It ports `packages/recorder` (`detect.ts`, `liveEnvelope.ts`, `useRecorder.ts`,
`useMetronome.ts`, `format.ts`) and depends on AVFoundation and Accelerate only.

## The raw input is recorded, the gain is applied at stop

The level a take needs is the loudest moment of the take, which is known only when it ends. Levelling
while recording would either guess or pump. So the input is written unprocessed and
`TakeEncoder` applies one factor, `0.9 / truePeak` (capped at 32), when the take stops. The
envelope is levelled separately, from its own RMS peak, so the waveform fills its height whatever
the audio's gain. The live envelope and the moments are drawn from the raw samples and
re-levelled on the fly: the floor of the detector is a share of the peak, so the gain does not
change what is found.

## The working file is lossless, the m4a is encoded once

During a take the audio goes to a 16-bit CAF, off the audio thread. AAC is written once, at stop,
from that file: encoding twice (record to AAC, then level and re-encode) would stack two lossy
generations on every take. A crash leaves the CAF, which `TakeRecorder.leftovers(in:)` finds, and
no header patching is needed to read it. The price is a short encode at stop, far faster than real
time.

## m4a, not WebM: no duration patch

A WebM from a recorder has no duration and must be patched to seek. An m4a written through
`AVAudioFile` carries its length and seeks from the first byte, so the iOS app has none of the
browser's `webmDuration` machinery. Opus is not offered by AVFoundation for files; AAC is.

## Continuing a take joins by decoding

AAC does not concatenate by bytes. Continuing a take decodes the earlier file and the new raw take
into one file, each part at its own gain: the earlier part is already levelled and is untouched,
the new one is levelled on its own peak, so both reach 0.9. The envelopes are appended, and the
result reports where the new part starts, which is where the drawn timeline puts it.

## The microphone is behind a protocol

`TakeRecorder` takes an `AudioInput`; `EngineInput` (an `AVAudioEngine` tap, mixed to mono) is the
device one. Pause stops the input, so the microphone indicator goes out while a take rests. A
dead input (a route lost, the engine reconfigured) pauses the take and says so on the event
stream. A low input rate, a Bluetooth headset's 16 kHz, gets an AAC bit rate the encoder accepts.

## Playback gain through an EQ

`AVAudioPlayerNode` volumes stop at 1, and a take recorded elsewhere may need more. The global gain
of an `AVAudioUnitEQ` goes to +24 dB, which covers the cap. One player plays at a time through
`PlaybackCoordinator`: starting one pauses the other. The metronome is not part of that rule, a
click under a take is the point.

## The playhead stays out of the waveform drawing

The player gives a position, never a drawn frame. The view moves a thin overlay by that position
on a display link; the waveform itself is drawn from the envelope and redrawn only when the
envelope changes. Following a 60 fps playhead with a full redraw costs more than it shows. The
position is derived from the node's render time with `Playhead`, a pure function, so a loop's
wrap is tested without sound.

## The metronome is sample-accurate, its callback is not

The click is generated frame by frame in an `AVAudioSourceNode`, so tempo does not drift with a
timer. A beat is reported to the UI from the main queue after its buffer, so a flash may trail the
click by a buffer. A `ClickGenerator` renders the same samples whatever the buffer size.

## What only a device can verify

The suite runs on the Mac with a fake input and an engine rendering offline. It cannot check: the
microphone permission flow, `.playAndRecord` routing (speaker, Bluetooth, headset), interruptions
by a call, `EngineInput` itself, the `dataPlayedBack` completion that ends a range at the speaker,
and the audible click. Those need a phone.
