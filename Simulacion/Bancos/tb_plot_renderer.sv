`timescale 1ns/1ps
module tb_plot_renderer;
localparam[23:0]BLACK=24'h000000,GRID=24'h202020,AXIS=24'h606060;
localparam[23:0]BORDER=24'h808080,WAVE=24'h00ff40,FFT=24'h00d8ff;
reg clk=1'b0;
always#5clk=~clk;
reg rst_n=1'b0;
reg[10:0]x=0;
reg[9:0]y=0;
reg de=0,hsync=0,vsync=0,mode_fft=0,front_valid=0;
wire rd_en;
wire[7:0]rd_wave_addr,rd_spectrum_addr;
reg rd_valid=0;
reg signed[15:0]wave_prev=0,wave_sample=0;
reg[17:0]spectrum_mag=0;
wire[7:0]rgb_r,rgb_g,rgb_b;
wire de_out,hsync_out,vsync_out;
integer pattern_set=0;
integer probes=0,checks=0;
reg[23:0]expected_current_rgb=BLACK;
reg[23:0]expected_previous_rgb=BLACK;
reg expected_previous_de=0,expected_previous_hs=0,expected_previous_vs=0;
plot_renderer dut(
.clk(clk),.rst_n(rst_n),.x(x),.y(y),.de(de),
.hsync(hsync),.vsync(vsync),.mode_fft(mode_fft),.front_valid(front_valid),
.rd_en(rd_en),.rd_wave_addr(rd_wave_addr),.rd_spectrum_addr(rd_spectrum_addr),
.rd_valid(rd_valid),.wave_prev(wave_prev),.wave_sample(wave_sample),
.spectrum_mag(spectrum_mag),.rgb_r(rgb_r),.rgb_g(rgb_g),.rgb_b(rgb_b),
.de_out(de_out),.hsync_out(hsync_out),.vsync_out(vsync_out)
);
function automatic signed[15:0]mock_wave(input integer address,dataset);
begin
case(dataset)
1:mock_wave=16'sh7fff;
2:mock_wave=16'sh8000;
3:mock_wave=(address==0)?16'sh8000:16'sh7fff;
4:mock_wave=(address==0)?16'sh7fff:16'sh8000;
5:mock_wave=-16'sd1;
10:mock_wave=address*128;
default:mock_wave=16'sd0;
endcase
end
endfunction
function automatic[17:0]mock_magnitude(input integer address,dataset);
begin
case(dataset)
6:mock_magnitude=18'd64;
7:mock_magnitude=18'd32704;
8:mock_magnitude=18'd185363;
9:mock_magnitude=18'd262143;
11:mock_magnitude=18'd63;
12:mock_magnitude=address*64;
default:mock_magnitude=18'd0;
endcase
end
endfunction
always@(posedge clk or negedge rst_n)begin
if(!rst_n)begin
rd_valid<=1'b0;
wave_prev<=16'sd0;
wave_sample<=16'sd0;
spectrum_mag<=18'd0;
end else begin
rd_valid<=rd_en;
if(rd_en)begin
wave_sample<=mock_wave(rd_wave_addr,pattern_set);
wave_prev<=mock_wave((rd_wave_addr==0)?0:(rd_wave_addr-1),pattern_set);
spectrum_mag<=mock_magnitude(rd_spectrum_addr,pattern_set);
end
end
end
always@(posedge clk)begin:output_scoreboard
reg[23:0]saved_rgb;
reg saved_de,saved_hs,saved_vs;
saved_rgb=expected_current_rgb;
saved_de=de;saved_hs=hsync;saved_vs=vsync;
#1;
checks=checks+1;
if(!rst_n)begin
if({rgb_r,rgb_g,rgb_b}!==BLACK||de_out||hsync_out||vsync_out)
$fatal(1,"RENDER: salidas no estan en reposo durante reset");
expected_previous_rgb=BLACK;
expected_previous_de=0;expected_previous_hs=0;expected_previous_vs=0;
end else begin
if({rgb_r,rgb_g,rgb_b}!==expected_previous_rgb||
de_out!==expected_previous_de||hsync_out!==expected_previous_hs||
vsync_out!==expected_previous_vs)
$fatal(1,
"RENDER t=%0t: RGB=%h esperado=%h DE/HS/VS=%b%b%b esperado=%b%b%b",
$time,{rgb_r,rgb_g,rgb_b},expected_previous_rgb,de_out,hsync_out,vsync_out,
expected_previous_de,expected_previous_hs,expected_previous_vs);
expected_previous_rgb=saved_rgb;
expected_previous_de=saved_de;
expected_previous_hs=saved_hs;
expected_previous_vs=saved_vs;
end
end
task automatic reset_dut;
begin
@(negedge clk);rst_n=0;
de=0;hsync=0;vsync=0;front_valid=0;
expected_current_rgb=BLACK;
#1;
if({rgb_r,rgb_g,rgb_b}!==BLACK||de_out||hsync_out||vsync_out||rd_en)
$fatal(1,"RENDER: reset asincrono no cancela pixel pendiente");
repeat(2)@(posedge clk);
#2rst_n=1;
end
endtask
task automatic probe(
input integer px,py,
input reg active,fft_mode,has_front,
input integer dataset,
input[23:0]expected_color,
input integer expected_wave_addr,expected_spec_addr
);
begin
@(negedge clk);
x=px;y=py;de=active;mode_fft=fft_mode;front_valid=has_front;
pattern_set=dataset;
hsync=probes[0];vsync=probes[1];probes=probes+1;
expected_current_rgb=expected_color;
#1;
if(rd_en!==(active&&has_front)||rd_wave_addr!==expected_wave_addr||
rd_spectrum_addr!==expected_spec_addr)
$fatal(1,"RENDER: solicitud en xy=%0d,%0d en=%b w=%0d s=%0d; esperado=%b,%0d,%0d",
px,py,rd_en,rd_wave_addr,rd_spectrum_addr,
active&&has_front,expected_wave_addr,expected_spec_addr);
@(posedge clk);#2;
end
endtask
initial begin
$dumpfile("plot_renderer.vcd");
$dumpvars(1,tb_plot_renderer);
reset_dut();
probe(50,50,1,0,0,0,BLACK,0,0);
probe(256,200,1,0,0,0,GRID,32,16);
probe(300,256,1,0,0,0,GRID,43,21);
probe(300,384,1,0,0,0,AXIS,43,21);
probe(300,384,1,1,0,0,GRID,43,21);
probe(128,200,1,0,0,0,AXIS,0,0);
probe(127,200,1,0,0,0,BORDER,0,0);
probe(1152,200,1,0,0,0,BORDER,255,128);
probe(1160,200,1,1,0,0,BORDER,255,128);
probe(300,127,1,0,0,0,BORDER,43,21);
probe(300,640,1,0,0,0,BORDER,43,21);
probe(300,384,1,0,1,0,WAVE,43,21);
probe(301,384,1,0,1,0,WAVE,43,21);
probe(301,383,1,0,1,0,BLACK,43,21);
probe(301,385,1,0,1,0,BLACK,43,21);
probe(301,129,1,0,1,1,WAVE,43,21);
probe(301,128,1,0,1,1,GRID,43,21);
probe(301,130,1,0,1,1,BLACK,43,21);
probe(301,639,1,0,1,2,WAVE,43,21);
probe(301,638,1,0,1,2,BLACK,43,21);
probe(301,385,1,0,1,5,WAVE,43,21);
probe(301,384,1,0,1,5,AXIS,43,21);
probe(132,200,1,0,1,3,WAVE,1,0);
probe(133,200,1,0,1,3,BLACK,1,0);
probe(133,129,1,0,1,3,WAVE,1,0);
probe(128,200,1,0,1,3,AXIS,0,0);
probe(128,639,1,0,1,3,WAVE,0,0);
probe(132,200,1,0,1,4,WAVE,1,0);
probe(135,200,1,0,1,4,BLACK,1,0);
probe(135,639,1,0,1,4,WAVE,1,0);
probe(1151,129,1,0,1,10,WAVE,255,127);
probe(1152,129,1,0,1,10,BORDER,255,128);
probe(301,639,1,1,1,0,AXIS,43,21);
probe(301,639,1,1,1,11,AXIS,43,21);
probe(301,639,1,1,1,6,FFT,43,21);
probe(301,638,1,1,1,6,BLACK,43,21);
probe(301,129,1,1,1,7,FFT,43,21);
probe(301,128,1,1,1,7,GRID,43,21);
probe(301,639,1,1,1,7,FFT,43,21);
probe(301,129,1,1,1,8,FFT,43,21);
probe(301,200,1,1,1,9,FFT,43,21);
probe(1151,513,1,1,1,12,FFT,255,127);
probe(1152,512,1,1,1,12,FFT,255,128);
probe(1153,511,1,1,1,12,BLACK,255,128);
probe(1159,200,1,1,1,8,FFT,255,128);
probe(1160,200,1,1,1,8,BORDER,255,128);
probe(301,384,1,0,1,0,WAVE,43,21);
probe(301,384,1,0,0,0,AXIS,43,21);
probe(301,200,1,1,0,8,BLACK,43,21);
probe(301,200,1,1,1,8,FFT,43,21);
probe(301,384,0,0,1,0,BLACK,43,21);
probe(1400,730,0,1,1,9,BLACK,255,128);
probe(301,129,1,1,1,8,FFT,43,21);
reset_dut();
probe(301,384,1,0,1,0,WAVE,43,21);
probe(301,384,1,0,0,0,AXIS,43,21);
probe(0,0,0,0,0,0,BLACK,0,0);
probe(0,0,0,0,0,0,BLACK,0,0);
$display("PASS: RENDERER RGB, %0d pixeles dirigidos/%0d ciclos comprobados; RAMsincrona, dosflancos, recorte y sincronismos",probes,checks);
$finish;
end
initial begin#100000;$fatal(1,"RENDER: timeout de pruebas dirigidas");end
endmodule
