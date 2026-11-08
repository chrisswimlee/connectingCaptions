# Credits

connectingCaptions is by Chris Swim Lee. Theater captions and type-this-listen are this product.

Speech recognition — the audio-capture graph (any input device: mic, USB/line-in, Bluetooth, virtual loopback), Parakeet, Whisper, Apple Speech, Cohere, and Nemotron — comes from [FluidVoice](https://github.com/altic-dev/FluidVoice) by altic-dev. Those files stay under GPLv3. Each Voice Engine file starts with `Upstream: FluidVoice (altic-dev), GPLv3`. Settings shows the same credit.

Do not rewrite those engines to look original. Take input-device capture and model fixes from FluidVoice. Do not take their dictation app: the notch, rewrite, prompt modes, spoken send, or spoken punctuation.

History encryption uses [SQLCipher](https://www.zetetic.net/sqlcipher/) 4.20.0 by Zetetic LLC, BSD-style license. The amalgamation and `LICENSE.txt` are in `ThirdParty/SQLCipher`. It is linked into the app binary with CommonCrypto.
