#!/bin/bash

# old filepaths, needs updating
CONFIG="/boot/firmware/config.txt"
HDMI1="/etc/hdmi_toggle/hdmi1.txt"
HDMI2="/etc/hdmi_toggle/hdmi2.txt"
TOGGLE="/etc/hdmi_toggle/hdmi_toggle.flag" # may need to "touch" this file initially

# Read toggle value, default to 1 if not present
if [[ -f "$TOGGLE" ]]; then
    MODE=$(<"$TOGGLE")
else
    MODE=1
fi

if [[ "$MODE" == "1" ]]; then
    HDMI_CONTENT=$(<"$HDMI1")
    NEXT_MODE=2
else
    HDMI_CONTENT=$(<"$HDMI2")
    NEXT_MODE=1
fi

awk -v hdmi="$HDMI_CONTENT" '
    BEGIN {inblock=0}
    /###start/ {print "###start"; inblock=1; next}
    /###end/ && inblock {print hdmi; print "###end"; inblock=0; next}
    {if (!inblock) print}
' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"

echo "$NEXT_MODE" > "$TOGGLE"
