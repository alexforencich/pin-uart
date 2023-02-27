# Pin UART Readme

GitHub repository: https://github.com/alexforencich/pin-uart

## Introduction

The pin UART is an FPGA board-level debugging and reverse-engineering utility.  The design drives pin names out of all of the IO pins on a device, which can then be probed with an oscilloscope with serial decode capability.

The build is scripted to generate the top-level HDL and pin constraint files based on the device pins.  Currently, the tool is a bit rough - only Vivado is supported, and the clocking configuration only supports STARTUPE2/STARTUPE3.

## Documentation

### `pin_uart` module

The `pin_uart` module is a simple state machine that will shift out the configured string when triggered, including appropriate start and stop bits.
