# Downgrade

## ATTENTION: 

NO RESPONSIBILITIES ARE TAKE, IF YOU BRICK YOUR DEVICE BY USING ANY OF THESE METHODS. THINK TWICE, READ AND UNDERSTAND THE CODE. USE IT ON YOUR OWN RISK.

Downgrading the firmware is not working through WebUI or the official flash.sh script which is available on stock firmwares. It's possible to store customized flashing scripts which will allow you to downgrade or flash any available firmware. 

tl;dr: The scripts in this repository disable all firmware checking mechanisms and flash the firmware even if it is not built for your device. If you flash a firmware e.g. for a V2 device you will brick your device - eventually permanentely.

## How To

1. Upload scripts to directory: ```/data```
2. Upload firmware file to ```/tmp```
3. Run flash script and read explanation: ```bash flash.sh```