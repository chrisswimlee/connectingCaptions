#!/bin/zsh
# Generates per-sentence voice clips and prints their durations.
cd "${0:A:h}/voice"
EN="Eddy (English (US))"; KO="Eddy (Korean (South Korea))"
say -v "$EN" -r 175 -o s1.aiff "Hi everyone, thanks for coming."
say -v "$EN" -r 175 -o s2.aiff "Half of you are hearing this in Korean."
say -v "$KO" -r 225 -o s2ko.aiff "여러분 중 절반은 한국어로 듣고 계십니다."
say -v "$EN" -r 180 -o s3.aiff "Tonight's demo is Connecting Captions."
say -v "$EN" -r 180 -o s5.aiff "And none of this needs the internet."
say -v "$EN" -r 185 -o s6.aiff "See you at the after-party."
for f in *.aiff; do printf "%s %s\n" "${f%.aiff}" "$(ffprobe -v error -show_entries format=duration -of csv=p=0 $f)"; done
