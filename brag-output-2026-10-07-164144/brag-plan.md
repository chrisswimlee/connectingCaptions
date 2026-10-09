# Connecting Captions: brag plan (privacy-first live interpreter)

**What it is:** a live interpreter for macOS. You speak and each sentence appears on screen, translated, when it is ready. It runs on Apple Speech and Apple Translation on the Mac itself.
**Who for:** presenters, teachers and speakers whose audience needs another language, and who don't want to upload their talk to a cloud caption service.
**Angle:** Why → How → What. The video uses the product's own mechanic: each line is typed as it is heard, then prints as a translated caption.
**Hook (0–2 s):** "A live interpreter shouldn't need the cloud." types word by word, then prints as Korean in Theater teal.
**Tone:** polished and warm. Music only, soft transitions. 22.6 s, 1920×1080, 30 fps.
**Identity:** the Theater board in dark mode (#141414), teal translated title, grey spoken undertone, real window chrome (I speak / Show as / Lectern·Watch / Listen), amber brand mark, SF Pro + Apple SD Gothic Neo.

| # | t (s) | Beat |
|---|---|---|
| WHY | 0–6.3 | Full-bleed Theater board. Line 1, the hook, is heard in the live bar and then prints as Korean: "A live interpreter shouldn't need the cloud." Line 2: "And your words should stay yours." |
| HOW | 6.3–12.3 | "Every step runs on this Mac." Inside a "This Mac" boundary, Mic → Apple Speech → Apple Translation → Theater light up in turn. A "Cloud API" box sits outside, its link cut. Real HUD from `docs/samples/LastListenLatency.json`: e2e 1.97 s · ASR 383 ms · MT 142 ms. Footnote: Speech Analyzer on macOS 26 + Apple Translation packs. |
| WHAT | 12.3–19.0 | The real Theater window with English ⇆ Korean and Listen on. Three sentences are heard in the live bar and print one by one. |
| NAME | 19.0–22.6 | Icon, "Connecting Captions", "A live interpreter that stays on your Mac.", Download free for Mac, local-host.ai/connectingCaptions. |

**Honesty notes:** the latency figures come from the committed sample. "On this Mac" is scoped to Speech Analyzer on macOS 26, because the legacy Apple Speech path sets `requiresOnDeviceRecognition = false`. The video has no "Wi-Fi off" or "works offline" claim.
**Sound:** a D-major bed that stays sparse in WHY, with a soft sub swell on each print. The pulse enters at HOW, a bell plays on each caption print and each node lighting up, a quiet pitched tick plays per word, and a final chord lands on the name card.
