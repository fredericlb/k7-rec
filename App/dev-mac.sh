#!/bin/bash
# The Mac dev loop: builds the Catalyst app in App/build/dev, runs it, and rebuilds and relaunches on save.
# It never touches an installed K7 REC: it only quits the process it launched itself (docs/mac.md, "Dev loop").
# Usage: App/dev-mac.sh [launch arguments], e.g. App/dev-mac.sh -OpenFirstSong YES -OpenTab chords
set -u

app_dir="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$app_dir")"
derived="$app_dir/build/dev"
bundle="$derived/Build/Products/Debug-maccatalyst/K7Rec.app"
binary="$bundle/Contents/MacOS/K7Rec"
stamp="$derived/.dev-stamp"
log="$derived/last-build.log"
watched=("$app_dir/Sources" "$app_dir/Resources" "$app_dir/project.yml")
for pkg in "$root"/Packages/*/; do watched+=("$pkg"Sources "$pkg"Package.swift); done
pid=""

say() { printf '\033[1;36m[dev]\033[0m %s\n' "$*"; }

# Another K7Rec running from outside the dev build is the user's own app: leave it, and refuse to share its library.
foreign=$(pgrep -f '/K7Rec.app/Contents/MacOS/K7Rec' | while read -r p; do
  ps -o command= -p "$p" | grep -qF "$bundle" || echo "$p"; done)
if [ -n "$foreign" ]; then
  say "K7 REC is already running (pid $foreign); quit it first, the dev build shares its library."
  exit 1
fi

generate() {
  say "xcodegen generate"
  (cd "$app_dir" && xcodegen generate --quiet) || return 1
}

build() {
  local start=$SECONDS
  say "building..."
  if (cd "$app_dir" && xcodebuild -project K7Rec.xcodeproj -scheme K7Rec -configuration Debug \
      -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath "$derived" build) >"$log" 2>&1; then
    say "built in $((SECONDS - start))s"
  else
    grep -E '^/.*: error:' "$log" | sort -u | head -30
    say "build failed, the running app is kept (full log: $log)"
    return 1
  fi
}

stop_app() {
  [ -n "$pid" ] || return 0
  kill "$pid" 2>/dev/null
  for _ in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  kill -9 "$pid" 2>/dev/null
  pid=""
}

launch() {
  stop_app
  "$binary" "$@" &
  pid=$!
  say "running (pid $pid); edit a file to rebuild, Ctrl-C to stop"
}

# The list of watched files: a new or removed file means XcodeGen must list it again.
inventory() { find "${watched[@]}" -type f ! -name '.*' 2>/dev/null | sort | md5; }

# Prints the first file changed since the stamp, else a folder that lost one, else nothing.
changed() {
  local hit
  hit=$(find "${watched[@]}" -newer "$stamp" -type f ! -name '.*' -print -quit 2>/dev/null)
  [ -n "$hit" ] || hit=$(find "${watched[@]}" -newer "$stamp" -type d -print -quit 2>/dev/null)
  echo "$hit"
}

trap 'stop_app; exit 0' INT TERM

mkdir -p "$derived"
[ -d "$app_dir/K7Rec.xcodeproj" ] || generate || exit 1
touch "$stamp"
files=$(inventory)
build || exit 1
launch "$@"

while true; do
  sleep 0.5
  # The app quit on its own (closed window, crash): the loop ends with it.
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then say "the app quit"; exit 0; fi
  file=$(changed)
  [ -n "$file" ] || continue
  sleep 0.3
  touch "$stamp"
  say "changed: ${file#"$root"/}"
  now=$(inventory)
  case "$file" in *project.yml|*Package.swift) files="" ;; esac
  if [ "$now" != "$files" ]; then generate || continue; files=$now; fi
  build && launch "$@"
done
