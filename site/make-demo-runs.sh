#!/bin/sh
# Regenerate site/demo-runs, the fixture the published demo is baked from.
#
# Not run by the build. The runs are committed so the site build needs only
# emacs, pandoc and pwsh; this is here so they are reproducible rather than
# three binaries nobody can account for. Needs ffmpeg.
#
# The numbers are F2 from FINDINGS.md: the same tape at three jump strengths,
# where drift ran +11.9 / +9.6 / +6.8 percent while the absolute error held near
# 12px. The demo therefore shows a real finding, and the clips encode the reach
# they claim: airtime is reach/speed, so the distance covered on screen is the
# measured value in the delta table.
set -e
cd "$(dirname "$0")"
OUT=demo-runs/dashguy/gap

command -v ffmpeg >/dev/null 2>&1 || { echo "need ffmpeg" >&2; exit 1; }
rm -rf demo-runs

# name  runId  runAt  claimed  measured  arc-height
set -- \
  "floaty 20260808-101500000 2026-08-08T10:15:00Z 104.6 117.0 62" \
  "stock  20260808-104200000 2026-08-08T10:42:00Z 126.6 138.7 74" \
  "poppy  20260808-111900000 2026-08-08T11:19:00Z 154.2 164.7 88"

T0=0.3667      # jump at frame 22 of a 60Hz tick
SPD=225        # px/s, constant: airtime is what reach varies by
GY=196         # ground top; the player is 20px tall and sits on it
DUR=1.85       # 111 frames, so duration equals frames/tickRate

for row in "$@"; do
  # shellcheck disable=SC2086
  set -- $row
  NAME=$1; RUNID=$2; AT=$3; CLAIMED=$4; MEASURED=$5; H=$6
  DIR="$OUT/$RUNID"
  mkdir -p "$DIR"

  D=$(awk "BEGIN{printf \"%.4f\", $MEASURED/$SPD}")
  Y="if(between(t\,$T0\,$T0+$D)\,$GY-$H*sin(PI*(t-$T0)/$D)\,$GY)"
  X="26+$SPD*t"

  # The moving box is an overlay, not a drawbox. In drawbox `t` is the THICKNESS
  # variable, not the timestamp, so an x/y expression using t silently evaluates
  # against 3 and puts the box off-screen. overlay is the filter whose x/y do get
  # time. The scenery stays drawbox because it never moves.
  #
  # 480x270 because the diff bay slot is about 460px wide; smaller is upscaled
  # and turns to mush on the one page meant to show the tool off.
  ffmpeg -y -loglevel error \
    -f lavfi -i "color=c=0x14151A:s=480x270:d=$DUR:r=60" \
    -f lavfi -i "color=c=0xFFB000:s=20x20:d=$DUR:r=60" \
    -f lavfi -i "color=c=0xFFB000:s=20x20:d=$DUR:r=60" \
    -filter_complex "\
[0]drawbox=x=0:y=216:w=480:h=54:color=0x2A2C34@1:t=fill,\
drawbox=x=0:y=216:w=480:h=3:color=0x6BE3A8@0.55:t=fill,\
drawbox=x=130:y=216:w=80:h=54:color=0x0A0B09@1:t=fill,\
drawbox=x=128:y=216:w=3:h=54:color=0x6BE3A8@0.40:t=fill,\
drawbox=x=210:y=216:w=3:h=54:color=0x6BE3A8@0.40:t=fill[bg];\
[2]format=yuva420p,colorchannelmixer=aa=0.30[trail];\
[bg][trail]overlay=x='($X)-16':y='($Y)+3'[t1];\
[t1][1]overlay=x='$X':y='$Y'[out]" \
    -map "[out]" -c:v libx264 -pix_fmt yuv420p -preset veryslow -crf 28 -an \
    "$DIR/clip.mp4"

  LANDX=$(awk "BEGIN{printf \"%.2f\", 132.0+$MEASURED}")
  cat > "$DIR/result.json" <<JSON
{
  "scenario": "gap",
  "label": "$NAME",
  "run_at": "$AT",
  "frames": 111,
  "capture_stride": 1,
  "passed": true,
  "reason": "tape exhausted",
  "checks": [
    { "name": "left_the_ground", "ok": true, "detail": "jumps=1" },
    { "name": "cleared_the_gap", "ok": true, "detail": "deaths=0" }
  ],
  "counts": { "jump": 1, "land": 2 },
  "claims": { "reach": $CLAIMED },
  "events": [
    { "frame": 9,  "name": "land", "x": 80.0,    "y": 383.93 },
    { "frame": 22, "name": "jump", "x": 132.0,   "y": 383.93 },
    { "frame": 53, "name": "land", "x": $LANDX,  "y": 383.93 }
  ]
}
JSON
  echo "$NAME  reach=${MEASURED}px  airtime=${D}s  $(du -k "$DIR/clip.mp4" | cut -f1)KB"
done

echo "wrote $OUT"
