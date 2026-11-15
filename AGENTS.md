# Rules for this repository

- **A source file over 500 lines is suspect.** Split it unless there is a reason, and say it.
- **Comments and docs are in English.** A file header is at most 10 lines; a comment inside a body is
  exactly one line. Long rationale goes to the zone's page in `docs/`, and the code points at it.
- **A doc page carries CHOICES, not mechanism**, and describes the project AS IT IS: no history, no
  "it used to be". Where a past failure justifies a decision, state the hazard in the present tense.
- **Icons are SF Symbols**, never an emoji.
- **Libraries**: GRDB and Yams only. Anything else third-party is shown with its strengths and
  weaknesses and asked about first.
- **Tests are sized to what they prove** (seconds). Anything needing a microphone or a route stays
  behind a protocol with a fake, and what only a device can verify is listed in `docs/`.
- The app builds in Swift 6 language mode; the packages test on the Mac with `swift test`.
