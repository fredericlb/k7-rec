# Audio

`Packages/RehearsalAudio` records a take, reads its envelope, finds its moments, plays it back and
clicks a tempo. It ports `packages/recorder` (`detect.ts`, `liveEnvelope.ts`, `useRecorder.ts`,
`useMetronome.ts`, `format.ts`) and depends on AVFoundation and Accelerate only.

## The raw input is recorded, the gain is applied at stop

The level a take needs is the loudest moment of the take, which is known only when it ends. Levelling
while recording would either guess or pump. So the input is written unprocessed and
`TakeEncoder` applies one factor, `0.9 / truePeak` (capped at 32), when the take stops. That factor
is baked into the file: `TakeResult.appliedGain` is informative, and a phone take is played at 1,
so the stored gain of such a take is 1 and never the player's input. The envelope is levelled
separately, from its own loudest RMS bucket (not its loudest instant), so the waveform fills its
height whatever the audio's gain. The live envelope and the moments are drawn from the raw samples and
re-levelled on the fly: the floor of the detector is a share of the peak, so the gain does not
change what is found.

## The working file is lossless, the m4a is encoded once

During a take the audio goes to a 32-bit float CAF, off the audio thread: the gain applied at stop
can reach 32x, which would raise a 16-bit file's quantisation noise by 30 dB. AAC is written once, at stop,
from that file: encoding twice (record to AAC, then level and re-encode) would stack two lossy
generations on every take. The price is a short encode at stop, far faster than real time.

## A crash loses nothing, and the raw file outlives the encode

A crash leaves the CAF, which reads without header patching, and a small JSON sidecar written at
start beside it: the earlier take's path and envelope, the two things the file cannot say.
Everything else (rate, frames, true peak, envelope) is read back from the CAF, which is always the
more complete witness, so the sidecar holds no counter that could go stale.
`TakeRecorder.leftovers(in:)` lists them and `recover(raw:)` encodes one as `stop` would; a
continuation keeps its earlier part when that file is still there, otherwise it comes back as a
separate take. A continuation that crashed before its first frame recovers as its earlier
part alone.

The raw file and the sidecar are deleted by `TakeResult.confirmSaved()`, never by the recorder:
an m4a that no saved row names is unfindable, so the raw input is the only copy until the caller
has saved the row.

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
device one, on a fresh engine each run since one that lived through a media-services reset is
unusable. Pause stops the input, so the microphone indicator goes out while a take rests. A dead
input (a route lost, the engine reconfigured) pauses the take and says so on the event stream, as
does an interruption; `pauseReason` tells the UI which. A low input rate, a Bluetooth headset's
16 kHz, gets an AAC bit rate the encoder accepts.

A take that cannot start says why, in words the person can act on. A device whose audio server is
stuck refuses to start input and output together: `kAUStartIO` hangs five seconds, then answers
CoreAudio's `'nope'`, in every `.playAndRecord` mode, while `.record` alone still works; a restart of
the device clears it. `EngineInput` turns that code into `audioStuck`, which tells the person to
restart. An input that reports 0 Hz is refused as `noInputFormat` before any file exists, since no
raw file can be written at that rate. The app's alert shows the recorder's reason, not a generic line.

## The session is behind a protocol too

`SessionHost` carries the interruption and media-services-reset notifications and the session
activation, so the Mac suite drives them with a fake. An interruption pauses the take, stops the
player (position kept) and the metronome; its end resumes nothing, because only the user knows
whether the rehearsal goes on. `resume()` activates the session again, which an interruption
deactivates. An engine reconfiguration (a route lost) stops the player and the metronome the
same way. The metronome says so through `onHalt` (never from `stop()`), so its owner stops
showing a click that no longer runs.

While a headset take runs, the click and playback keep its hands-free profile: dropping it would
move the input to the built-in microphone and pause the take.

## A resume on another rate is an error, not a conversion

The raw file, the envelope and the clock are fixed to the rate the take started at. A route change
while paused can move the input to another rate; `resume()` then throws `rateChanged` and leaves
the take paused with everything kept. The caller ends it with `stop()` and continues with
`start(extending:)`, which the encoder joins across rates. Converting live to the take's rate would
put a resampler on the tap path, and its filter delay and tail would be a second silent way to be
wrong; the explicit error keeps the file correct and costs one extra tap at a rare event, as for a
stream rate change in `packages/ui-rehearsal/docs/chainSource.md`.

## Bluetooth is A2DP unless the headset's microphone is asked for

With `.playAndRecord` and both Bluetooth options set the system prefers hands-free ports, so every
playback and click through earphones would be narrowband mono. The session therefore allows A2DP
only, and `.allowBluetoothHFP` is added for a take recorded with `headsetInput: true`. With A2DP
alone the input stays the phone's microphone, so plugging in earphones mid-take does not change
the input rate either.

## Playback gain through an EQ

`AVAudioPlayerNode` volumes stop at 1, and a take recorded elsewhere may need more. The global gain
of an `AVAudioUnitEQ` goes to +24 dB, so two in series reach +48 dB, past the recorder's 32x
(+30.1 dB) that a take may carry. One player plays at a time through
`PlaybackCoordinator`: starting one pauses the other. The metronome is not part of that rule, a
click under a take is the point.

## A transposed song is pitch-shifted, its tempo kept

`TakePlayer` and `StemPlayer` put an `AVAudioUnitTimePitch` before the gain (after the stems' own mixer for
the stems): Apple's phase-vocoder shifter, so no library is added, and it changes the pitch in cents with the
rate left at 1. At 0 semitones it is bypassed, so a take or an untransposed song is heard untouched. The
shifter reads ahead of what it outputs, so while it shifts the playhead runs about 50 ms early; the offline
test checks the pitch (an octave doubles a tone) and that the playhead still moves at the file's own speed.

## The player meters what is heard

A tap after the gain keeps the RMS of the last buffer (`TakePlayer.outputRMS`), so the level is what comes out,
the take's gain included; it reads 0 unless the player plays. The tap's closure is made outside the main actor:
the audio thread calls it, and a closure made in the main-actor initializer would be main-actor code and trap.

## The playhead stays out of the waveform drawing

The player gives a position and `Playhead` derives it from the node's render time, a pure function
tested without sound; how it is drawn is the app's (`docs/app.md`).

## The metronome is sample-accurate, its callback is not

The click is generated frame by frame in an `AVAudioSourceNode`, so tempo does not drift with a
timer. A beat is reported when its click reaches the speaker: the render runs ahead of the sound
by the IO buffer plus the output latency, so the callback is delayed by the session's figures,
and a beat still pending when the metronome stops is dropped. A `ClickGenerator` renders the same
samples whatever the buffer size.

## What only a device can verify

The suite runs on the Mac with a fake input and an engine rendering offline. It cannot check: the
microphone permission flow, `.playAndRecord` routing (speaker, Bluetooth, headset), the real
interruption and media-services-reset notifications, a CAF left by a killed process, the rate a
headset really reports, `EngineInput` itself (its `audioStuck` mapping included), the beat callback's alignment with the click, the `dataPlayedBack` completion that ends a range at the speaker,
the audible click, and how a shifted song sounds (the shifter's smearing of transients). Those need a phone.
