Edison V3 CC2538
================

This tool flashes the CC2538 on the gateway with firmware.

It can only be used on Edison Gateway V3 because the earlier versions didn't
have the UART pins connected to the Edison.

Edison Binary
-------------

The default binary comes from the
[Edison Forward app](https://github.com/lab11/G2/tree/master/contiki/apps/edisonFWD).


Trouble Shooting
----------------
If flash_cc2538.sh returns "ERROR: No serial port found", manually specify the serial port 
by adding "-p /dev/ttyUSB0" to the line calling cc2538-bsl.py (line 15).
