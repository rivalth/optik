# OptikWake

Keyword spotting for Optik's wake word, on the device.

Most of `Sources/OptikWake` is adapted from the `SpeechWakeWord` and
`AudioCommon` modules of [soniqo/speech-swift](https://github.com/soniqo/speech-swift)
0.0.29, licensed under Apache-2.0 (`LICENSE`). Each adapted file says so at the
top and names Optik's changes. The model is icefall's KWS Zipformer
(gigaspeech, Apache-2.0), in the Core ML export
`aufklarer/KWS-Zipformer-3M-CoreML-INT8`.

Optik's changes, made for the idle CPU budget (`docs/02-mimari.md` 6):

- No model download or third-party packages: the model loads from a folder.
  speech-swift as a dependency resolved 40 packages for this one module.
- `ModelRunners.swift`: every Core ML input and output buffer is allocated once.
  Without output backings Core ML took a new IOSurface for every prediction, and
  the buffer pool bookkeeping cost more than the model.
- `SwiftJoiner.swift`: the joiner (`W · tanh(enc + dec) + b`) runs with
  Accelerate from the model's own weights instead of ~100 Core ML calls a second.
- `GatedSession.swift`: the encoder runs only while sound rises above the
  room's floor and background, with a 0.8 s pre-roll.

Measured on an M2 (live microphone, 100 ms buffers, process CPU):

| Version | CPU |
| :-- | :-- |
| speech-swift as is | 5.5 % |
| Reused buffers + Swift joiner | 2.6–3.2 % |
| With the sound gate, quiet room | 0.57 % (capture alone 0.51 %) |
| With the sound gate, a film playing | 0.67–1.99 % |
