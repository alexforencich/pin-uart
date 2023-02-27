# Copyright (c) 2023 Alex Forencich
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

set_property design_mode PinPlanning [current_fileset]
open_io_design

# all GPIO pins
set pins [get_package_pins -filter {IS_GENERAL_PURPOSE==1}]

# sort pins by name
proc sort_bga_pins {pins} {
    foreach pin $pins {lappend pairs [list $pin [regsub {^\D\d+$} $pin {_&}]]}
    foreach pair [lsort -index 1 -dictionary $pairs] {lappend result [lindex $pair 0]}
    return $result
}

set pins [sort_bga_pins $pins]

# filter pins
if {[info exists skip_pins_by_index]} {
    foreach x $skip_pins_by_index {
        set pins [lreplace $pins $x $x]
    }
}

if {[info exists skip_pins_by_name]} {
    foreach x $skip_pins_by_name {
        set idx [lsearch $pins $x]
        set pins [lreplace $pins $idx $idx]
    }
}

# configuration

# clock source
if { ![info exists clk_src] } {
    set clk_src "STARTUPE3"
}

# frequency of clock source (in Hz)
if { ![info exists clk_freq] } {
    set clk_freq "50000000"
}
# worst-case period for timing analysis (in ns)
if { ![info exists clk_period] } {
    set clk_period "15"
}

# desired baud rate
if { ![info exists baud] } {
    set baud "115200"
}
# number of groups to shift at the same time
# more groups reduces collisions at the expense of repetition rate
if { ![info exists group_count] } {
    set group_count "32"
}

# iostandard for all pins
if { ![info exists iostandard] } {
    set iostandard "LVCMOS18"
}


# write out top-level verilog file
set fp [open "fpga.v" w]

puts $fp "/*

Copyright (c) 2023 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the \"Software\"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: Verilog 2001

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * 
 */
module fpga
("

for { set i 0 } { $i < [llength $pins] } { incr i } {
    set pin [lindex $pins $i]
    if { $i < [expr [llength $pins]-1 ] } {
        puts $fp "    output wire $pin,"
    } else {
        puts $fp "    output wire $pin"
    }
}

puts $fp ");

wire clk;
"

if {$clk_src == "STARTUPE2"} {

    puts $fp "// Internal clock sourced from ring oscillator
wire int_clk;
wire int_clk_bufg;

STARTUPE2
startupe2_inst (
    .CFGCLK(),
    .CFGMCLK(int_clk),
    .EOS(),
    .CLK(1'b0),
    .GSR(1'b0),
    .GTS(1'b0),
    .KEYCLEARB(1'b1),
    .PACK(1'b0),
    .PREQ(),
    .USRCCLKO(1'b0),
    .USRCCLKTS(1'b1),
    .USRDONEO(1'b0),
    .USRDONETS(1'b1)
);

BUFG
clk_bufg_inst (
    .I(int_clk),
    .O(int_clk_bufg)
);

assign clk = int_clk_bufg;"

} elseif {$clk_src == "STARTUPE3"} {

    puts $fp "// Internal clock sourced from ring oscillator
wire int_clk;
wire int_clk_bufg;

STARTUPE3
startupe3_inst (
    .CFGCLK(),
    .CFGMCLK(int_clk),
    .DI(),
    .DO(4'b0000),
    .DTS(4'b1111),
    .EOS(),
    .FCSBO(1'b0),
    .FCSBTS(1'b1),
    .GSR(1'b0),
    .GTS(1'b0),
    .KEYCLEARB(1'b1),
    .PACK(1'b0),
    .PREQ(),
    .USRCCLKO(1'b0),
    .USRCCLKTS(1'b1),
    .USRDONEO(1'b0),
    .USRDONETS(1'b1)
);

BUFG
clk_bufg_inst (
    .I(int_clk),
    .O(int_clk_bufg)
);

assign clk = int_clk_bufg;"

}

puts $fp "
localparam CLK_FREQ = $clk_freq;
localparam BAUD = $baud;
localparam PRESCALE = CLK_FREQ / BAUD;
localparam CL_PRESCALE = \$clog2(PRESCALE);

localparam PIN_COUNT = [llength $pins];

localparam GROUP_COUNT = $group_count;
localparam CL_GROUP_COUNT = \$clog2(GROUP_COUNT);

reg shift_rst_reg = 1'b0;
reg \[CL_GROUP_COUNT-1:0\] group_select_reg = 0;
reg \[GROUP_COUNT-1:0\] shift_reg = 1'b0;

reg \[CL_PRESCALE-1:0\] prescale_reg = PRESCALE;
reg \[5:0\] shift_count_reg = 0;

always @(posedge clk) begin
    shift_rst_reg <= 1'b0;
    shift_reg <= 0;

    if (prescale_reg) begin
        prescale_reg <= prescale_reg - 1;
    end else begin
        prescale_reg <= PRESCALE;
        if (shift_count_reg) begin
            shift_count_reg <= shift_count_reg - 1;
            shift_reg\[group_select_reg\] <= 1'b1;
        end else begin
            shift_count_reg <= 6'h3f;
            shift_rst_reg <= 1'b1;
            if (group_select_reg < GROUP_COUNT) begin
                group_select_reg <= group_select_reg + 1;
            end else begin
                group_select_reg <= 0;
            end
        end
    end
end
"

for { set i 0 } { $i < [llength $pins] } { incr i } {
    set pin [lindex $pins $i]
    puts $fp "pin_uart #(.NAME(\"${pin}\")) pin_${pin}_uart_inst (.clk(clk), .rst(shift_rst_reg), .shift(shift_reg\[${i}%GROUP_COUNT\]), .out(${pin}));"
}

puts $fp "
endmodule

`resetall"

close $fp

set fp [open "fpga.xdc" w]

# write out pin constraints file
puts $fp "# Copyright (c) 2023 Alex Forencich
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the \"Software\"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# clock
"

if {$clk_src == "STARTUPE2"} {

    puts $fp "# Fcfgmclk is 65 MHz with no specified tolerance, rounding to 10 ns period
create_clock -period 10 -name cfgmclk \[get_pins startupe2_inst/CFGMCLK\]"

} elseif {$clk_src == "STARTUPE3"} {

    puts $fp "# Fcfgmclk is 50 MHz +/- 15%, rounding to 15 ns period
create_clock -period 15 -name cfgmclk \[get_pins startupe3_inst/CFGMCLK\]"

}
    puts $fp "
# pins"

foreach pin $pins {
    puts $fp "set_property -dict {LOC $pin IOSTANDARD $iostandard} \[get_ports $pin\]"
}

close $fp

close_design
set_property design_mode RTL [current_fileset]

