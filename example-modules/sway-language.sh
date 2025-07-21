#!/bin/sh
get_input() {
    xkbcli list | grep "description: $layout_description\s*$" -B 50 | tac | grep layout | head -n1 | sed -E "s/- layout: '(.*)'/\1/"
}
layout_description=$(swaymsg -t get_inputs | jq '.[].xkb_active_layout_name' -r --unbuffered | grep -v null)
get_input
swaymsg -t subscribe -m '["input"]' | jq '.input.xkb_active_layout_name' -r --unbuffered | while read layout_description 
do
    get_input
done

