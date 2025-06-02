# Xiaomi AX5400 CB0401 v1 Collection

### Unlock 5G Standalone + Band n75

The router has a Quectel RG520N-EB installed, which was loaded with a customized firmware (RG520NEBDCR01A13M4G_XM).
Magenta (thank you very much, kind regards) deactivates the n75 band via firmware and additionally all 5G_SA bands.

The bands can be enabled via at+command. The default configuration is written again with every restart. It is therefore necessary to create a startup script to unlock the bands again and again.

Since neither minicom nor screen is installed, it makes sense to open a terminal window to read the result of AT commands and a second terminal window to send AT commands

Terminal window for reading the commands:

```cat /dev/ttyUSB2```

Terminal Window for sending commands:
```
Display all possible bands:
echo -e 'AT+QNWPREFCFG="ue_capability_band"\r' > /dev/ttyUSB2

Enable Standalone (Bands):
echo -e 'AT+QNWPREFCFG="nr5g_disable_mode",0\r' > /dev/ttyUSB2

Enable Band n75 5G_NSA:
echo -e 'AT+QNWPREFCFG="nr5g_band",1:3:7:28:38:75:78\r' > /dev/ttyUSB2

Enable Band n75 5G_SA:
echo -e 'AT+QNWPREFCFG="nsa_nr5g_band",1:3:7:28:38:75:78\r' > /dev/ttyUSB2
```

I was not able to test whether the router also connects to band n75, as it is not yet activated here. Standalone works without any problems.
