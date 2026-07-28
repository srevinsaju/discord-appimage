#!/usr/bin/env bash
set -euo pipefail

readonly channel="${1:-}"
readonly repository="${GITHUB_REPOSITORY:-srevinsaju/discord-appimage}"
readonly build_root="$PWD/build"
readonly app_dir="$build_root/AppDir"
readonly bootstrap_dir="$build_root/bootstrap"
readonly updater_dir="$build_root/updater"
readonly dist_dir="$PWD/dist"
readonly appimagetool="$build_root/appimagetool-x86_64.AppImage"

case "$channel" in
  stable)
    readonly bootstrap_url="https://discord.com/api/download?platform=linux&format=tar.gz"
    readonly bootstrap_app_dir="Discord"
    readonly discord_binary="Discord"
    readonly release_tag="stable"
    ;;
  ptb)
    readonly bootstrap_url="https://discord.com/api/download/ptb?platform=linux&format=tar.gz"
    readonly bootstrap_app_dir="DiscordPTB"
    readonly discord_binary="DiscordPTB"
    readonly release_tag="ptb"
    ;;
  canary)
    readonly bootstrap_url="https://discord.com/api/download/canary?platform=linux&format=tar.gz"
    readonly bootstrap_app_dir="DiscordCanary"
    readonly discord_binary="DiscordCanary"
    readonly release_tag="canary"
    ;;
  *)
    echo "usage: $0 stable|ptb|canary" >&2
    exit 2
    ;;
esac

assert_app_dir() {
  local candidate_app_dir="$1"
  local candidate_build_info="$candidate_app_dir/resources/build_info.json"
  local candidate_standalone_modules="$candidate_app_dir/resources/standalone_modules"
  local module_links

  [[ -x "$candidate_app_dir/$discord_binary" ]]
  [[ -x "$candidate_app_dir/AppRun" ]]
  [[ -f "$candidate_app_dir/discord.desktop" ]]
  [[ -f "$candidate_build_info" ]]
  [[ "$(jq -r '.releaseChannel' "$candidate_build_info")" == "$channel" ]]
  [[ "$(jq -r '.standaloneModules' "$candidate_build_info")" == "true" ]]
  [[ "$(jq -r '.disableUpdater' "$candidate_build_info")" == "true" ]]
  [[ "$(jq -r '.version' "$candidate_build_info")" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [[ -d "$candidate_standalone_modules" ]]

  shopt -s nullglob
  module_links=("$candidate_standalone_modules"/*)
  shopt -u nullglob
  (( ${#module_links[@]} > 0 ))

  for module_link in "${module_links[@]}"; do
    [[ -L "$module_link" ]]
    [[ -d "$module_link" ]]
  done
}

[[ "$repository" == */* ]]
[[ ! -e "$build_root" ]]
[[ ! -e "$dist_dir" ]]

mkdir -p "$bootstrap_dir" "$updater_dir" "$dist_dir"

curl --fail --location --silent --show-error "$bootstrap_url" |
  tar -xz -C "$bootstrap_dir"

readonly updater_bootstrap="$bootstrap_dir/$bootstrap_app_dir/updater_bootstrap"
[[ -f "$updater_bootstrap" ]]
chmod +x "$updater_bootstrap"
"$updater_bootstrap" --no-zenity "$updater_dir" "$channel" https://updates.discord.com/

shopt -s nullglob
downloaded_app_dirs=("$updater_dir"/app-*)
shopt -u nullglob
(( ${#downloaded_app_dirs[@]} == 1 ))
mv "${downloaded_app_dirs[0]}" "$app_dir"

cp "$PWD/AppRun" "$app_dir/AppRun"
cp "$PWD/discord.desktop" "$app_dir/discord.desktop"
chmod +x "$app_dir/AppRun"

readonly build_info="$app_dir/resources/build_info.json"
readonly updated_build_info="$build_info.updated"
jq '.standaloneModules = true | .disableUpdater = true' "$build_info" > "$updated_build_info"
mv "$updated_build_info" "$build_info"

readonly standalone_modules="$app_dir/resources/standalone_modules"
mkdir "$standalone_modules"
shopt -s nullglob
module_dirs=("$app_dir"/modules/*/*)
shopt -u nullglob
(( ${#module_dirs[@]} > 0 ))

for module_dir in "${module_dirs[@]}"; do
  module_version_dir="$(basename "$(dirname "$module_dir")")"
  module_name="$(basename "$module_dir")"
  [[ ! -e "$standalone_modules/$module_name" ]]
  ln -s "../../modules/$module_version_dir/$module_name" "$standalone_modules/$module_name"
done

assert_app_dir "$app_dir"

curl --fail --location --silent --show-error \
  https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage \
  -o "$appimagetool"
chmod +x "$appimagetool"

version="$(jq -r '.version' "$build_info")"
readonly version
readonly repository_owner="${repository%%/*}"
readonly repository_name="${repository#*/}"
readonly update_information="gh-releases-zsync|$repository_owner|$repository_name|$release_tag|Discord*.AppImage.zsync"
readonly output_appimage="$dist_dir/Discord-$version-x86_64.AppImage"

(
  cd "$dist_dir"
  APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 \
    "$appimagetool" "$app_dir" -n -u "$update_information" "$(basename "$output_appimage")"
)
[[ -s "$output_appimage" ]]
[[ -s "$output_appimage.zsync" ]]

mkdir "$build_root/extracted"
(
  cd "$build_root/extracted"
  "$output_appimage" --appimage-extract >/dev/null
)
assert_app_dir "$build_root/extracted/squashfs-root"
