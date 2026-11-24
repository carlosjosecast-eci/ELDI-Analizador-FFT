`timescale 1ns/1ps
module tb_video_timing_720p;
reg clk=1'b0;
always#5clk=~clk;
reg rst_n=1'b0;
wire[10:0]x;
wire[9:0]y;
wire de,hsync,vsync,frame_start;
integer h,v,active_count,hs_count,vs_count,frame_count;
integer line_active,line_hs;
integer checks=0;
video_timing_720p dut(
.clk(clk),.rst_n(rst_n),.x(x),.y(y),.de(de),
.hsync(hsync),.vsync(vsync),.frame_start(frame_start)
);
task automatic check_pixel(input integer expected_x,expected_y);
reg expected_de,expected_hs,expected_vs,expected_start;
begin
expected_de=(expected_x<1280)&&(expected_y<720);
expected_hs=(expected_x>=1390)&&(expected_x<1430);
expected_vs=(expected_y>=725)&&(expected_y<730);
expected_start=(expected_x==0)&&(expected_y==0);
checks=checks+1;
if(x!==expected_x||y!==expected_y||
de!==expected_de||hsync!==expected_hs||
vsync!==expected_vs||frame_start!==expected_start)
$fatal(1,
"TIMING t=%0t: xy=%0d,%0d esperado=%0d,%0d de/hs/vs/fs=%b%b%b%b esperado=%b%b%b%b",
$time,x,y,expected_x,expected_y,de,hsync,vsync,
frame_start,expected_de,expected_hs,expected_vs,expected_start);
end
endtask
task automatic reset_dut;
begin
@(negedge clk);rst_n=1'b0;
#1;
if(x!==11'd0||y!==10'd0||de||hsync||vsync||frame_start)
$fatal(1,"TIMING: reset no devuelve origen con controles bajos");
repeat(2)@(posedge clk);
#2rst_n=1'b1;
#1;
check_pixel(0,0);
end
endtask
initial begin
active_count=0;hs_count=0;vs_count=0;frame_count=0;
reset_dut();
for(v=0;v<750;v=v+1)begin
line_active=0;
line_hs=0;
for(h=0;h<1650;h=h+1)begin
check_pixel(h,v);
if(de)begin active_count=active_count+1;line_active=line_active+1;end
if(hsync)begin hs_count=hs_count+1;line_hs=line_hs+1;end
if(vsync)vs_count=vs_count+1;
if(frame_start)frame_count=frame_count+1;
@(posedge clk);#1;
end
if(line_hs!=40||line_active!=((v<720)?1280:0))
$fatal(1,"TIMING linea%0d: activos%0d HS%0d",v,line_active,line_hs);
end
check_pixel(0,0);
if(active_count!=921600||hs_count!=30000||
vs_count!=8250||frame_count!=1)
$fatal(1,"TIMING: conteos activos=%0d HS=%0d VS=%0d frames=%0d",
active_count,hs_count,vs_count,frame_count);
repeat(137)@(posedge clk);
#1;
check_pixel(137,0);
reset_dut();
for(h=0;h<200;h=h+1)begin
check_pixel(h,0);
@(posedge clk);#1;
end
$display("PASS: TIMING720p, cuadro1650x750, activos921600, HS40, VS5lineas, wrap y reset, %0d comprobaciones",checks);
$finish;
end
initial begin
$dumpfile("video_timing_720p.vcd");
$dumpvars(1,tb_video_timing_720p);
repeat(5000)@(posedge clk);
$dumpoff;
end
initial begin#15000000;$fatal(1,"TIMING: timeout de cuadro completo");end
endmodule
