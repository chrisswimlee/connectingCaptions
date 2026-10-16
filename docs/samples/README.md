# Samples

`LastListenLatency.json` is from a real Theater Listen on the maintainer Mac (`thermal` nominal; e2e 1969 ms, ASR 383 ms, MT 142 ms). Hosted CI only stores it.

## Two different files, and only one of them is proof

**A scorer self-test** lives at `Tests/ConnectingCaptionsIntegrationTests/Fixtures/quality-vectors.jsonl`. It pins what "one unit" means for word and character error, so the Swift scorer and `scripts/score-theater-talk.py` cannot quietly drift into measuring different things. It is checked by `sh scripts/test-quality-score.sh`, which CI runs.

A green run there means the **ruler is honest**. It does not mean the app is good at subtitling anything — most of those vectors are invented strings chosen to exercise the arithmetic, not transcribed speech. Do not read a passing scorer check as a quality result.

**A quality measurement** needs a reference JSONL: real audio, transcribed by a person, in the language being spoken. That file does not exist yet. `docs/STAGE_SCORE.md` explains how to make one; `scripts/test-quality-score.sh` starts scoring it automatically the day it lands here, and refuses a mean built from fewer than 12 lines.

Do not invent WER or invent reference lines. A reference you wrote is not a reference — it is a guess about what the engine would say, and it will pass.
