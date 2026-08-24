#!/bin/sh
# One-time rename of the old app's on-disk state. Existing Hmail state
# always wins: combining two stores without understanding their contents could
# overwrite a newer account or cache.
set -eu

move_once() {
  old=$1
  new=$2
  if [ -e "$old" ] && [ ! -e "$new" ]; then
    mv "$old" "$new"
  fi
}

config_home=${XDG_CONFIG_HOME:-$HOME/.config}
cache_home=${XDG_CACHE_HOME:-$HOME/.cache}
data_home=${XDG_DATA_HOME:-$HOME/.local/share}

# Newest previous name first: if an Omamail store exists it is the freshest,
# and the older omarchy-gmail store is then left alone rather than merged.
move_once "$config_home/omamail" "$config_home/hmail"
move_once "$cache_home/omamail" "$cache_home/hmail"
move_once "$data_home/omamail" "$data_home/hmail"
move_once "$config_home/omarchy-gmail" "$config_home/hmail"
move_once "$cache_home/omarchy-gmail" "$cache_home/hmail"
