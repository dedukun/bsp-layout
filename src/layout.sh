#!/usr/bin/env bash

VERSION="0.0.3";

export ROOT="/usr/lib/bsp-layout";
source "$ROOT/utils/desktop.sh";
source "$ROOT/utils/state.sh";

LAYOUTS="$ROOT/layouts";

HELP_TEXT="
Usage: bsp-layout command [args]

Commands:
  set <layout> [desktop_selector] -- [options]      - Will apply the layout to the selected desktop
  once <layout> [desktop_selector] -- [options]     - Will apply the layout on the current set of nodes
  get <desktop_selector>                            - Will print the layout assigned to a given desktop
  remove <desktop_selector>                         - Will disable the layout
  layouts                                           - Will list all available layouts
  version                                           - Displays the version number of the tool
  help                                              - See this help menu

Layout options:
  tall,wide,rtall,rwide
    --master-size 0.6         Set the master window size
";

# Layouts provided by bsp out of the box
BSP_DEFAULT_LAYOUTS="tiled\nmonocle";

# Kill old layout process
kill_layout() {
  old_pid="$(get_desktop_options "$1" | valueof pid)";
  kill $old_pid 2> /dev/null || true;
}

remove_listener() {
  desktop=$1;
  [[ -z "$desktop" ]] && desktop=$(get_focused_desktop);

  kill_layout "$desktop";

  # Reset process id and layout
  set_desktop_option $desktop 'layout' "";
  set_desktop_option $desktop 'pid'    "";
}

run_layout() {
  local layout_file="$LAYOUTS/$1.sh"; shift;

  # GUARD: Check if layout exists
  [[ ! -f $layout_file ]] && echo "Layout does not exist" && exit 1;

  bash "$layout_file" $*;
}

start_listener() {
  layout=$1; shift;
  selected_desktop=$1; shift;
  [[ "$selected_desktop" == "--" ]] && selected_desktop="";

  args=$@;

  # Set selected desktop to currently focused desktop if option is not specified
  [[ -z "$selected_desktop" ]] && selected_desktop=$(get_focused_desktop);

  # If it is a bsp default layout, set that
  if (echo -e "$BSP_DEFAULT_LAYOUTS" | grep "^$layout$"); then
    remove_listener "$selected_desktop";
    bspc desktop "$selected_desktop" -l "$layout";
    exit 0;
  fi

  recalculate_layout() { run_layout $layout $args 2> /dev/null || true; }

  # Recalculate styles as soon as they are set if it is on the selected desktop
  [[ "$(get_focused_desktop)" = "$selected_desktop" ]] && recalculate_layout;

  # Then listen to node changes and recalculate as required
  bspc subscribe node_{add,remove,transfer}  | while read line; do
    event=$(echo "$line" | awk '{print $1}');
    arg_index=$([[ "$event" == "node_transfer" ]] && echo "6" || echo "3");
    desktop_id=$(echo "$line" | awk "{print \$$arg_index}");
    desktop_name=$(get_desktop_name_from_id "$desktop_id");

    [[ "$desktop_name" = "$selected_desktop" ]] && recalculate_layout;
  done &

  LAYOUT_PID=$!; # PID of the listener in the background
  disown;

  # Kill old layout
  kill_layout $selected_desktop;

  # Set current layout
  set_desktop_option $selected_desktop 'layout' "$layout";
  set_desktop_option $selected_desktop 'pid'    "$LAYOUT_PID";

  echo "[$LAYOUT_PID]";
}

reload_layouts() {
  list_desktops | while read desktop; do
    layout=$(get_desktop_options "$desktop" | valueof layout);
    [[ ! -z "$layout" ]] && start_listener $layout $desktop;
  done;
}

action=$1; shift;

case "$action" in
  reload)     reload_layouts ;;
  once)       run_layout "$1" ;;
  set)        start_listener "$@" ;;
  get)        layout=$(get_desktop_options "$1" | valueof layout); echo "${layout:-"default"}" ;;
  remove)     remove_listener "$1" ;;
  layouts)    echo -e "$BSP_DEFAULT_LAYOUTS"; ls "$LAYOUTS" | sed -e 's/\.sh$//'; ;;
  help)       echo -e "$HELP_TEXT" ;;
  version)    echo "$VERSION" ;;
  *)          echo -e "$HELP_TEXT" && exit 1 ;;
esac
