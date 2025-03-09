#!/bin/bash
# Save to ~/Documents/generate_mac_inventory.sh
# Make executable with: chmod +x ~/Documents/generate_mac_inventory.sh

OUTFILE=~/Documents/my_mac_inventory.md
DATE=$(date +"%Y-%m-%d")

echo "# My Mac Setup Inventory - $DATE" > $OUTFILE
echo "" >> $OUTFILE

echo "## Installed Applications" >> $OUTFILE
echo "" >> $OUTFILE
ls -1 /Applications | sort >> $OUTFILE
echo "" >> $OUTFILE

echo "## Homebrew Packages" >> $OUTFILE
echo "" >> $OUTFILE
if command -v brew &> /dev/null; then
  brew list >> $OUTFILE
else
  echo "Homebrew not installed" >> $OUTFILE
fi
echo "" >> $OUTFILE

echo "## Custom Automator Workflows" >> $OUTFILE
echo "" >> $OUTFILE
ls -1 ~/Library/Services | sort >> $OUTFILE
echo "" >> $OUTFILE

echo "Inventory saved to $OUTFILE"
