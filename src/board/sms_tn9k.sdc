create_clock -name clk27    -period 37.037 -waveform {0 18.518} [get_ports {clk27}]
create_clock -name memclk   -period 11.574 -waveform {0 5.787}     [get_nets {memclk}]
create_clock -name memclk_p -period 11.574 -waveform {2.894 8.681} [get_nets {memclk_p}]
create_clock -name clk      -period 46.296 -waveform {0 23.148} [get_nets {clk}]
create_clock -name clk_pix  -period 37.037 -waveform {0 18.518} [get_nets {clk_pix_Z}]
set_clock_groups -asynchronous -group [get_clocks {clk27}] -group [get_clocks {clk memclk memclk_p}] -group [get_clocks {clk_pix}]
set_false_path -from [get_ports {btn_s1_n btn_s2_n btn_start1 btn_credit joy_up joy_down joy_left joy_right joy_fire joy_btn2 sd_dat0}]
// request address / data -> memclk: stable two more memclk before their use;
// PSRAM word -> q_ps: read 6 clk after the request.
set_multicycle_path -from [get_clocks {clk}] -to [get_clocks {memclk}] -setup -end 2
set_multicycle_path -from [get_clocks {clk}] -to [get_clocks {memclk}] -hold -end 1
set_multicycle_path -from [get_clocks {memclk}] -to [get_clocks {clk}] -setup -start 2
set_multicycle_path -from [get_clocks {memclk}] -to [get_clocks {clk}] -hold -start 1
