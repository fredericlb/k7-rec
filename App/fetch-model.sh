#!/bin/sh
# Fetches the stem model (HTDemucs Core ML, MIT, 287 MB zipped) into App/Models, which the app bundles (docs/stems.md).
set -e
cd "$(dirname "$0")"
[ -d Models/StemSeparator.mlpackage ] && { echo "Models/StemSeparator.mlpackage is already there"; exit 0; }
tmp=$(mktemp -d)
curl -fL -o "$tmp/model.zip" https://huggingface.co/slaughters85j/htdemucs-coreml/resolve/main/htdemucs.mlpackage.zip
unzip -q "$tmp/model.zip" -d "$tmp"
mkdir -p Models && mv "$tmp/htdemucs.mlpackage" Models/StemSeparator.mlpackage && rm -rf "$tmp"
echo "Installed Models/StemSeparator.mlpackage; run xcodegen generate"
