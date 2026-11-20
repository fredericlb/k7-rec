# Stems

`Packages/RehearsalStems` splits a song's own audio file into drums, bass, other and vocals, and plays
the four back with a mix. It depends on AVFoundation, Core ML and `RehearsalAudio` (the playback floor).

## The model is bundled in the build, not in the repository

The weights are 407 MB and carry their own licence, so the repository does not hold them. `App/fetch-model.sh`
puts the MIT Core ML conversion of HTDemucs `slaughters85j/htdemucs-coreml` (FP32 only: FLOAT16 destroys the
reconstruction) in `App/Models` (git-ignored) as `StemSeparator.mlpackage`; the build compiles it into the app
as `StemSeparator.mlmodelc`, on the iPhone, the iPad and the Mac alike. Xcode generates no class for it
(`COREML_CODEGEN_LANGUAGE` is `None`): the generated `StemSeparator` would clash with the package's. A build
without the folder has no model; a `StemSeparator.mlpackage` dropped in the `Models` folder of Documents is
then compiled once and kept beside it as a `.mlmodelc`. Without either, the sheet says what to install and
offers no work.

## The model contract is waveform in, waveform out

Input `mix`: Float32 `[1, 2, N]`, stereo at 44.1 kHz, `N` = 343 980 (7.8 s) for HTDemucs. Output: Float32
`[1, 8, N]` (paired channels: drums, bass, other, vocals) or `[1, 4, 2, N]`, in `Stem` case order. The
STFT, the network and the inverse STFT are all inside the model, so the app does no spectral work. A model
that needs a spectrogram outside (Spleeter, Open-Unmix) does not fit and has to be wrapped first.

## The model runs on the CPU

The package's own notes say the GPU path is faster on a Mac but the Neural Engine rejects its unrolled
inverse STFT; `CoreMLSegmentModel` defaults to `.cpuOnly`, the one setting the converter validated on every
device. The cost is time, not correctness.

## Memory is one segment, however long the song

The file is read, resampled and cut into segments of `N` frames that overlap by one second; each is run
alone and the overlap is cross-faded linearly, so the four stems are written to AAC as the segments come
and nothing but one segment and one overlap is held. A phone with 3 to 4 GB of RAM can then separate a
long song when the model itself fits.

## The set is written whole or not at all

The stems go to a hidden sibling folder that replaces `stems/` of the song folder in one move. A failure
or a cancel leaves the old set (or none) and no partial folder. A set with a missing file is no set.

## Separation runs in the foreground

The sheet is the only view of the work and closing it cancels. A suspended app would stop the model
mid-segment, and a half-set is worth nothing, so nothing is kept to resume. The screen stays awake while it
runs, since auto-lock would suspend the app. A device under 3.5 GB of RAM is told the system may close the app;
the threshold is a guess until a phone measures it, and the button stays enabled.

## Stems follow the audio they came from

They live in the song's folder (`stems/`), so Files shows them. A re-import replaces the song's folder and
does not carry them over: the audio may have changed, and a set that no longer matches is worse than none.

## Playback has its own transport

`StemPlayer` starts the four nodes at one shared host time so they stay in step; it takes the playback floor
like `TakePlayer`, so the song's player gives way. It plays the whole file, with no loop range or moment.
A mute and a solo are one `StemMix` rule: a solo silences every other stem and wins over a mute.

- **The instrumental is made with the set.** After the four stems are written, drums, bass and other are summed into
  `stems/instrumental.m4a` (a second AAC encode, a few seconds) before the set replaces the old one, so a new
  separation or a removal takes it along. A set made before that has none: the first switch mixes it, once.
  The switch is a microphone button left of Info in the song's tab row, shown when the song has stems. The
  choice is the reader's, kept per song; the player knows the two versions under two ids, and a switch carries
  the position and the playing state over. Without the file the song plays in full whatever was chosen.

## Only a device can say

- How long a model takes on a given iPhone, and whether iOS keeps the app alive with 3 to 4 GB of RAM.
- That the Neural Engine runs the model rather than the CPU, and the heat of a four-minute song.
- Time and memory of a 407 MB FP32 model on a phone: the Mac test runs the real model, a segment in about 3 s.
- That `.cpuOnly` is the right setting on iOS; the GPU may be faster and was not measured there.
