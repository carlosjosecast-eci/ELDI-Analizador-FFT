`timescale 1ns/1ps
module view_selector_case#(
parameter integer N=4
)(
input wire clk,
output reg done
);
reg rst_n;
reg key_s2;
reg frame_start;
wire mode_fft;
reg expected_mode;
integer checks;
integer i;
view_selector#(.DEBOUNCE_CYCLES(N))dut(
.clk(clk),
.rst_n(rst_n),
.key_s2(key_s2),
.frame_start(frame_start),
.mode_fft(mode_fft)
);
task automatic check_output;
begin
checks=checks+1;
if(mode_fft!==expected_mode)
$fatal(1,
"N=%0d comprobacion=%0d t=%0t: modo=%b esperado=%b key=%b frame=%b reset=%b",
N,checks,$time,mode_fft,expected_mode,
key_s2,frame_start,rst_n);
end
endtask
task automatic cycle(
input reg next_key,
input reg next_frame,
input reg expected_after
);
begin
@(negedge clk);
key_s2=next_key;
frame_start=next_frame;
expected_mode=expected_after;
@(posedge clk);
#1;
check_output();
end
endtask
task automatic hold_key(
input reg level,
input integer cycles,
input reg expected_after
);
integer j;
begin
for(j=0;j<cycles;j=j+1)
cycle(level,1'b0,expected_after);
end
endtask
task automatic publish(
input reg level,
input reg expected_after
);
begin
cycle(level,1'b1,expected_after);
cycle(level,1'b0,expected_after);
end
endtask
task automatic reset_case(input reg held_key);
begin
@(negedge clk);
rst_n=1'b0;
key_s2=held_key;
frame_start=1'b0;
expected_mode=1'b0;
#1;
check_output();
repeat(2)@(posedge clk);
#1;
rst_n=1'b1;
end
endtask
task automatic unsampled_pulse(
input reg stable_level,
input reg expected_after
);
begin
@(negedge clk);
frame_start=1'b0;
expected_mode=expected_after;
#1key_s2=~stable_level;
#1key_s2=stable_level;
@(posedge clk);
#1;
check_output();
end
endtask
task automatic bounce(
input reg stable_level,
input reg expected_after
);
integer j;
begin
for(j=0;j<4;j=j+1)begin
if(N==1)begin
unsampled_pulse(stable_level,expected_after);
end else begin
cycle(~stable_level,1'b0,expected_after);
cycle(stable_level,1'b0,expected_after);
end
end
hold_key(stable_level,N+2,expected_after);
end
endtask
initial begin
rst_n=1'b0;
key_s2=1'b0;
frame_start=1'b0;
expected_mode=1'b0;
checks=0;
done=1'b0;
reset_case(1'b0);
hold_key(1'b0,N+2,1'b0);
publish(1'b0,1'b0);
if(N>1)begin
hold_key(1'b1,N-1,1'b0);
hold_key(1'b0,N+2,1'b0);
end else begin
unsampled_pulse(1'b0,1'b0);
hold_key(1'b0,N+2,1'b0);
end
publish(1'b0,1'b0);
bounce(1'b0,1'b0);
publish(1'b0,1'b0);
hold_key(1'b1,N+2,1'b0);
publish(1'b1,1'b1);
reset_case(1'b0);
hold_key(1'b1,N+1,1'b0);
cycle(1'b1,1'b1,1'b0);
cycle(1'b1,1'b0,1'b0);
publish(1'b1,1'b1);
for(i=0;i<24;i=i+1)begin
cycle(1'b1,1'b0,1'b1);
publish(1'b1,1'b1);
end
bounce(1'b1,1'b1);
publish(1'b1,1'b1);
if(N>1)begin
hold_key(1'b0,N-1,1'b1);
hold_key(1'b1,N+2,1'b1);
publish(1'b1,1'b1);
end
hold_key(1'b0,N+2,1'b1);
hold_key(1'b1,N+2,1'b1);
publish(1'b1,1'b0);
reset_case(1'b0);
hold_key(1'b1,N+2,1'b0);
hold_key(1'b0,N+2,1'b0);
hold_key(1'b1,N+2,1'b0);
hold_key(1'b0,N+2,1'b0);
publish(1'b0,1'b0);
reset_case(1'b0);
for(i=0;i<3;i=i+1)begin
hold_key(1'b1,N+2,1'b0);
hold_key(1'b0,N+2,1'b0);
end
publish(1'b0,1'b1);
reset_case(1'b1);
hold_key(1'b1,N+1,1'b0);
cycle(1'b1,1'b1,1'b0);
publish(1'b1,1'b1);
hold_key(1'b1,N+4,1'b1);
publish(1'b1,1'b1);
reset_case(1'b0);
hold_key(1'b1,N+2,1'b0);
reset_case(1'b0);
hold_key(1'b0,N+2,1'b0);
publish(1'b0,1'b0);
hold_key(1'b1,N+1,1'b0);
reset_case(1'b0);
hold_key(1'b0,N+2,1'b0);
publish(1'b0,1'b0);
$display("PASS: DEBOUNCE_CYCLES=%0d, comprobaciones=%0d",N,checks);
done=1'b1;
end
endmodule
module tb_view_selector;
reg clk=1'b0;
wire done_n4;
wire done_n1;
always#5clk=~clk;
view_selector_case#(.N(4))case_n4(
.clk(clk),.done(done_n4)
);
view_selector_case#(.N(1))case_n1(
.clk(clk),.done(done_n1)
);
initial begin
$dumpfile("view_selector.vcd");
$dumpvars(0,tb_view_selector);
wait(done_n4&&done_n1);
$display("PASS: selector de vista, todos los casos completados.");
$finish;
end
initial begin
#50000;
$fatal(1,"TIMEOUT: el testbench no termino");
end
endmodule
