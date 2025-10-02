#!/usr/bin/env bash
# call_sip.sh - notifier with X + Y math challenge (X = tasks today)
# Self-contained: generates digit WAVs (0..9) once and assembles numbers per call.
# Usage: sudo /root/call_sip.sh "Title" "Content" <target> [max_attempts]

set -x
set -Eeuo pipefail
IFS=$'\n\t'

### ---------- Config ----------
#SPEEDPORT_TRUNK="speedport"
#SOUNDS_DIR="/var/lib/asterisk/sounds/custom"
SOUNDS_DIR="$(mktemp --directory --suffix=asterisk_voicegen)" #/tmp/callz/sounds/custom/"
#TASKS_FILE="/var/lib/asterisk/tasks.txt"
TASKS_FILE="/tmp/callz/tasks.txt"

# TODO whats the proper way to do this ?! -z ?
CALLFILE_DIR="/var/spool/asterisk/outgoing"
if [ ! -v MODEL_PATH ]; then
	MODEL_PATH="en_US-amy-low.onnx"
fi

# TODO whats the proper way to do this ?! -z ?
if [ ! -v AUDIO_ARTIFACT_USER  ]; then
	AUDIO_ARTIFACT_USER="asterisk"
fi

# TODO whats the proper way to do this ?! -z ?
if [ ! -v AUDIO_ARTIFACT_GROUP ]; then
	AUDIO_ARTIFACT_GROUP="asterisk"
fi


TITLE_BASE="title_text_tts"
CONTENT_BASE="content_tts"

CHALLENGE_PROMPT_BASE="challenge_prompt"
WORD_PLUS_BASE="word_plus"
WORD_EQUALS_BASE="word_equals"
ENTER_CODE_BASE="enter_code"

DIGIT_PREFIX="digit_"
GAP_BASE="gap_200ms"

# per-call assembled numbers
NUMX_BASE="num_x"
NUMY_BASE="num_y"

### ---------- Helpers ----------
need_bin() { command -v "$1" >/dev/null 2>&1 || { echo "Missing binary: $1"; exit 4; }; }

say_text_to_wav() {
  # $1=text, $2=outfile (keep same SoX pipeline you used before; it works on your box)
  printf "%s" "$1" \
    | piper --model "$MODEL_PATH" --output_file - \
    | sox -t wavpcm - -r 8000 -c 1 -b 16 "$2"
  chown $AUDIO_ARTIFACT_USER:$AUDIO_ARTIFACT_GROUP "$2" || true
  chmod 640 "$2"
}

make_gap_if_missing() {
  local out="$1"
  [ -f "$out" ] && return 0
  sox -n -r 8000 -c 1 -b 16 "$out" trim 0.0 0.2
  chown $AUDIO_ARTIFACT_USER:$AUDIO_ARTIFACT_GROUP "$out" || true
  chmod 640 "$out"
}

make_digit_if_missing() {
  local d="$1"
  local f="${SOUNDS_DIR}/${DIGIT_PREFIX}${d}.wav"
  [ -f "$f" ] && return 0
  say_text_to_wav "$d" "$f"
  echo "Generated digit clip: $f"
}

assemble_number_wav() {
  # $1=number (>=0), $2=outfile
  local num="$1"
  local out="$2"
  local files=()
  local s="${SOUNDS_DIR}/${GAP_BASE}.wav"

  if [[ "$num" =~ ^[0-9]+$ ]]; then
    # shellcheck disable=SC2207
    local digits=($(echo "$num" | grep -o .))
  else
    say_text_to_wav "$num" "$out"
    return 0
  fi

  for i in "${!digits[@]}"; do
    files+=("${SOUNDS_DIR}/${DIGIT_PREFIX}${digits[$i]}.wav")
    if [ "$i" -lt "$((${#digits[@]} - 1))" ]; then
      files+=("$s")
    fi
  done

  sox "${files[@]}" "$out"
  chown $AUDIO_ARTIFACT_USER:$AUDIO_ARTIFACT_GROUP "$out" || true
  chmod 640 "$out"
}

normalize_pstn() {
  # strip spaces; if leading '+', replace with '00'
  local n
  n="$(echo "$1" | tr -d '[:space:]')"
  [[ "$n" == +* ]] && n="00${n:1}"
  echo "$n"
}

### ---------- Args ----------
if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  echo "Usage: $0 \"Title\" \"Content\" <target (1002 or +38517...)> [max_attempts]"
  exit 2
fi

TITLE_TEXT="$1"
CONTENT_TEXT="$2"
TARGET_RAW="$3"

MAX_ATTEMPTS=0
CHALLENGE_ENABLED=0
if [ "$#" -eq 4 ]; then
  if [[ "$4" =~ ^[0-9]+$ ]] && [ "$4" -gt 0 ]; then
    MAX_ATTEMPTS="$4"
    CHALLENGE_ENABLED=1
  else
    echo "Fourth argument must be a positive integer (max attempts)."
    exit 3
  fi
fi

### ---------- Preflight ----------
need_bin piper
need_bin sox
mkdir -p "$SOUNDS_DIR"
chown $AUDIO_ARTIFACT_USER:$AUDIO_ARTIFACT_GROUP "$SOUNDS_DIR" || true
chmod 750 "$SOUNDS_DIR"

# Fixed prompts (only once)
declare -A PROMPTS=(
  ["$CHALLENGE_PROMPT_BASE"]="Reminder. Please solve the challenge to hear the message."
  ["$WORD_PLUS_BASE"]="plus"
  ["$WORD_EQUALS_BASE"]="equals"
  ["$ENTER_CODE_BASE"]="Now enter the answer using the keypad."
)
for base in "${!PROMPTS[@]}"; do
  f="${SOUNDS_DIR}/${base}.wav"
  [ -f "$f" ] || { say_text_to_wav "${PROMPTS[$base]}" "$f"; echo "Generated $f"; }
done

# Digit atlas + small gap (only once)
make_gap_if_missing "${SOUNDS_DIR}/${GAP_BASE}.wav"
for d in {0..9}; do make_digit_if_missing "$d"; done

# Per-call TTS
say_text_to_wav "$TITLE_TEXT"   "${SOUNDS_DIR}/${TITLE_BASE}.wav"
say_text_to_wav "$CONTENT_TEXT" "${SOUNDS_DIR}/${CONTENT_BASE}.wav"

### ---------- Compute Challenge ----------
TODAY=$(date +%F)
if [ -f "$TASKS_FILE" ]; then
  TASKS_TODAY_COUNT=$(grep -c "^${TODAY}" "$TASKS_FILE" || true)
else
  TASKS_TODAY_COUNT=0
fi

RANDOM_NUMBER=$((RANDOM % 10))
CHALLENGE_NUMBER=$((TASKS_TODAY_COUNT + RANDOM_NUMBER))

# Per-call numbers (assembled from digits)
assemble_number_wav "$TASKS_TODAY_COUNT" "${SOUNDS_DIR}/${NUMX_BASE}.wav"
assemble_number_wav "$RANDOM_NUMBER"      "${SOUNDS_DIR}/${NUMY_BASE}.wav"

### ---------- Channel selection (FIXED to use Local channel) ----------
CHANNEL=""
# treat 1–4 digit all-numeric as local PJSIP ext
if [[ "$TARGET_RAW" =~ ^[0-9]{1,4}$ ]]; then
  CHANNEL="PJSIP/${TARGET_RAW}"
  echo "Target detected as local extension: ${TARGET_RAW}"
else
  PSTN="$(normalize_pstn "$TARGET_RAW")"
  # Use Local channel to go through dialplan - THIS IS THE FIX
  CHANNEL="Local/${PSTN}@from-internal"
  echo "Target detected as external number: ${PSTN} via dialplan"
fi

### ---------- Callfile ----------
CALLFILE_TMP=$(mktemp)
cat > "$CALLFILE_TMP" <<EOF
Channel: ${CHANNEL}
MaxRetries: 0
RetryTime: 60
WaitTime: 30
Context: notify-challenge
Extension: s
Priority: 1
SetVar: SOUNDS_DIR=${SOUNDS_DIR}
SetVar: TITLE_BASE=${TITLE_BASE}
SetVar: CONTENT_BASE=${CONTENT_BASE}
SetVar: CHALLENGE_ENABLED=${CHALLENGE_ENABLED}
SetVar: CHALLENGE_MAX_ATTEMPTS=${MAX_ATTEMPTS}
SetVar: CHALLENGE_PROMPT_BASE=${CHALLENGE_PROMPT_BASE}
SetVar: WORD_PLUS_BASE=${WORD_PLUS_BASE}
SetVar: WORD_EQUALS_BASE=${WORD_EQUALS_BASE}
SetVar: ENTER_CODE_BASE=${ENTER_CODE_BASE}
SetVar: TASKS_TODAY_COUNT=${TASKS_TODAY_COUNT}
SetVar: RANDOM_NUMBER=${RANDOM_NUMBER}
SetVar: CHALLENGE_NUMBER=${CHALLENGE_NUMBER}
SetVar: NUMX_BASE=${NUMX_BASE}
SetVar: NUMY_BASE=${NUMY_BASE}
EOF

chown $AUDIO_ARTIFACT_USER:$AUDIO_ARTIFACT_GROUP "$CALLFILE_TMP"
chmod 660 "$CALLFILE_TMP"
cp "$CALLFILE_TMP" "/tmp/frag-notify_${TARGET_RAW}_$(date +%s).call"
mv "$CALLFILE_TMP" "${CALLFILE_DIR}/notify_${TARGET_RAW}_$(date +%s).call"

echo "Callfile moved to ${CALLFILE_DIR}. Asterisk should pick it up immediately."
if [ "${CHALLENGE_ENABLED}" -eq 1 ]; then
  echo "Challenge enabled. ${TASKS_TODAY_COUNT} + ${RANDOM_NUMBER} = ${CHALLENGE_NUMBER} (max attempts: ${MAX_ATTEMPTS})."
fi

exit 0
