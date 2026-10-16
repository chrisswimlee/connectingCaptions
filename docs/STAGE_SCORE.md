# Score a Theater talk

Theater → Board → Export → **Quality review (JSONL)** now prepares the worksheet
from the full Listen, including lines that scrolled off the board. Fill the empty
human references before scoring. The [release validation guide](RELEASE_VALIDATION.md)
describes recording, review, omissions, per-language gates and JSON reports.

Do not invent WER or HUD numbers. After a real Listen:

1. Export bilingual text from the visible Theater board.
2. Make a reference file with one JSON object per line. Layout only — these lines are not a scored talk:

```json
{"languageID":"en","reference":"Today we trained the model.","hypothesis":"Today we trained the model."}
{"languageID":"en","reference":"The next lecture starts at noon.","hypothesis":"The next lecture starts at noon."}
{"languageID":"en","reference":"Please take a seat.","hypothesis":"Please take a seat."}
{"languageID":"ko","reference":"오늘 모델을 학습했습니다.","hypothesis":"오늘 모델을 학습했습니다."}
{"languageID":"ja","reference":"今日はモデルを学習しました。","hypothesis":"今日はモデルを学習しました。"}
```

3. Run:

```
python3 scripts/score-theater-talk.py reference.jsonl
```

Optional: pass `LastListenLatency.json` as the second argument. The script prints mean error and whether every line would pass the 15% “would I show this” bar.

English uses word error. Korean, Japanese, and Thai use character error. Same rule as `TheaterQualityScore`.

**"Same rule" has to be checked, not asserted.** Compact scripts are counted by *character*, and a character is not one thing: Thai stacks vowels and tones as combining marks on a consonant, and Korean spacing is separator code. The two scorers used to disagree about the same line — Swift read grapheme clusters, Python read code points — and Thai marks were invisible to *both*, so `ครับ` and `ครั๊บ` scored a perfect 0.0. `Tests/ConnectingCaptionsIntegrationTests/Fixtures/quality-vectors.jsonl` pins what a unit is, and `sh scripts/test-quality-score.sh` fails if either scorer drifts away from it. Run that before you quote a number from either side.

The same fold also feeds `isCloseTokenSubstitution` in `TranslationClauseSegmenter`, which uses `<= 0.34` to decide whether a changed word is a slip of the tongue or a different content word. Checked against realistic near-miss pairs in each script (Thai tone marks, Korean case and verb endings, the Japanese long-vowel mark, Chinese character drops): none of them crossed 0.34 either way, so that gate behaves as it did before. It has **not** been re-tuned, and it should not be tuned from a spreadsheet — that threshold needs a real recording.

A 9 on ASR is about 8% English and 12% Korean/Thai on a 20-minute close-mic talk. A 9 on translation is every line at or under 15% against a bilingual reference.

## Maintainer first talk

Do this once on a real Mac before you treat Theater as proven. Do not invent WER.

1. One English lectern (or Korean / Thai / Japanese). Microphone only — real mic capture, no loopback or line-in routing.
2. Export bilingual text from the visible Theater board.
3. Build `reference.jsonl` and run `python3 scripts/score-theater-talk.py reference.jsonl [LastListenLatency.json]`.
4. Check the script output and `LastListenLatency.json` into [docs/samples/](samples/). That file is the project proof. Hosted CI only stores it. Watch is not a required pair.

## Samples

`docs/samples/LastListenLatency.json` is a real lectern clock from the maintainer Mac: e2e 1969 ms, ASR 383 ms, MT 142 ms, thermal nominal. Hosted CI only stores it. A bilingual WER/CER score is still missing because there is no reference JSONL for that talk. Do not invent one. Re-score a talk on this Mac after a Listen-host change. The audience now sees a clause when it commits, so e2e is the wait they feel. Do not invent a new number for this change.

Korean and Japanese leftover commits on EOU, silence, or Stop. The 1.0 s / 6.0 s settle helpers are unused; do not invent a new land clock. A long connective can print as a caption; that is a clause rule, not a new clock.

Thai wrap uses Apple's Thai word tokenizer. A word wider than the available line
still splits at a grapheme boundary so the caption remains visible. Word wrapping
does not change recognition quality or the measured clock.

There is no live-row retype counter. A painted line is immutable. Do not invent a replacement score. Hosted CI cannot caption a live tab.
