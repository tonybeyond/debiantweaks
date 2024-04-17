#!/bin/bash
#-------------------------------------------------------------------------------
# textrecon.sh
#
# This script takes a screenshot using Flameshot, performs OCR on the screenshot
# using Tesseract with English as the language, and copies the OCR output to the
# clipboard using xclip. The screenshot is saved to a temporary file that is
# deleted after the OCR is performed.
#
# Usage:
#
#   textrecon.sh
#
# Requirements:
#
#   - Flameshot: A screenshot tool that allows you to select a region of the
#     screen to capture.
#   - Tesseract: An OCR engine that can recognize text in images.
#   - xclip: A command-line utility that allows you to copy text to the clipboard.
#
#-------------------------------------------------------------------------------

# Take a screenshot area with Flameshot and save it to a temporary file
flameshot gui -p ~/Pictures/Screenshots/screenshot.png

# Perform OCR on the screenshot and copy the text to the clipboard
tesseract ~/Pictures/Screenshots/screenshot.png - -l eng | xclip -selection clipboard

# Remove the temporary file
rm ~/Pictures/Screenshots/screenshot.png
