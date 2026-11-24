`timescale 1ns/1ps
module adc_model_integracion_fd73(
input wire enabled,adc_convst,adc_cs_n,adc_rd_n,adc_reset,
output reg adc_busy=1'b0,
output wire adc_fd,
output wire[7:0]adc_db
);
reg ready=1'b0;
reg[15:0]result_word=0;
reg[7:0]bus_byte=0;
reg fd_valid=1'b0;
integer ordinal=0;
integer bytes_read=0;
wire selected=enabled&&!adc_reset&&ready&&!adc_cs_n&&!adc_rd_n;
assign adc_fd=selected?fd_valid:1'bz;
assign adc_db=selected&&fd_valid?bus_byte:8'hzz;
function automatic signed[15:0]tone(input integer index);
tone=$rtoi(8192.0*$cos(6.283185307179586*(index%64)/64.0));
endfunction
always@(posedge adc_reset)begin
adc_busy=1'b0;
ready=1'b0;
fd_valid=1'b0;
ordinal=0;
bytes_read=0;
end
always@(posedge adc_convst)begin
if(enabled&&!adc_reset)begin
if(adc_busy||ready||!adc_cs_n)
$fatal(1,"INT FINAL: CONVST antes de terminar la lectura anterior");
#17;
adc_busy=1'b1;
#4183;
result_word=tone(ordinal);
ordinal=ordinal+1;
ready=1'b1;
adc_busy=1'b0;
end
end
always@(negedge adc_cs_n)begin
if(enabled&&(adc_busy||!ready||!adc_rd_n))
$fatal(1,"INT FINAL: CS antes de conversión lista");
bytes_read=0;
end
always@(negedge adc_rd_n)begin
if(enabled)begin
if(adc_cs_n||adc_reset||!ready||adc_busy||bytes_read>=2)
$fatal(1,"INT FINAL: RD fuera de la lectura de AIN1 después de BUSY");
fd_valid=1'b0;
bus_byte=(bytes_read==0)?result_word[15:8]:result_word[7:0];
bytes_read=bytes_read+1;
#37;
fd_valid=1'b1;
end
end
always@(posedge adc_cs_n)begin
if(enabled&&ready)begin
if(bytes_read!=2)$fatal(1,"INT FINAL: AIN1 exige dos bytes");
ready=1'b0;
end
end
endmodule
module tb_integracion_final#(
parameter bit STANDALONE=1'b1
)(
output reg done=1'b0
);
localparam realtime ADC_HALF_NS=500.0/27.0;
localparam realtime PIX_HALF_NS=500.0/74.25;
reg clk27=1'b0;
reg pix_base_clk=1'b0;
reg pixel_clock_running=1'b1;
wire pix_clk=pix_base_clk&&pixel_clock_running;
reg rst27_n=1'b0;
reg rstpix_n=1'b0;
reg key_s2=1'b0;
always#(ADC_HALF_NS)clk27=~clk27;
initial begin
#2.731;
forever#(PIX_HALF_NS)pix_base_clk=~pix_base_clk;
end
wire adc_busy,adc_fd,adc_convst,adc_cs_n,adc_rd_n,adc_reset;
wire[7:0]adc_db;
wire mode_fft,adc_fault,processor_fault,display_fault,front_valid;
wire[31:0]front_seq;
wire[23:0]rgb;
wire video_de,video_hsync,video_vsync;
wire[9:0]tmds_red,tmds_green,tmds_blue;
wire sample_valid,frame_begin,wave_valid,spectrum_valid,frame_done;
wire[31:0]frame_seq;
wire[7:0]wave_index,spectrum_index;
wire signed[15:0]sample_signed,wave_sample;
wire[17:0]spectrum_mag;
analyzer_core#(.ADC_STARTUP_CYCLES(8),.DEBOUNCE_CYCLES(4))dut(
.clk27(clk27),.pix_clk(pix_clk),.rst27_n(rst27_n),.rstpix_n(rstpix_n),
.key_s2(key_s2),.adc_busy(adc_busy),.adc_fd(adc_fd),.adc_db(adc_db),
.adc_convst(adc_convst),.adc_cs_n(adc_cs_n),.adc_rd_n(adc_rd_n),.adc_reset(adc_reset),
.tmds_red(tmds_red),.tmds_green(tmds_green),.tmds_blue(tmds_blue),
.mode_fft(mode_fft),.adc_fault(adc_fault),.processor_fault(processor_fault),
.display_fault(display_fault),.front_valid(front_valid),.front_seq(front_seq),
.rgb_r(rgb[23:16]),.rgb_g(rgb[15:8]),.rgb_b(rgb[7:0]),
.video_de(video_de),.video_hsync(video_hsync),.video_vsync(video_vsync),
.debug_sample_valid(sample_valid),.debug_sample_signed(sample_signed),
.debug_frame_begin(frame_begin),.debug_frame_seq(frame_seq),
.debug_wave_valid(wave_valid),.debug_wave_index(wave_index),.debug_wave_sample(wave_sample),
.debug_spectrum_valid(spectrum_valid),.debug_spectrum_index(spectrum_index),
.debug_spectrum_mag(spectrum_mag),.debug_frame_done(frame_done)
);
adc_model_integracion_fd73 adc_model(
.enabled(rst27_n),.adc_convst(adc_convst),.adc_cs_n(adc_cs_n),.adc_rd_n(adc_rd_n),
.adc_reset(adc_reset),.adc_busy(adc_busy),.adc_fd(adc_fd),.adc_db(adc_db)
);
integer adc_cycle=0;
integer conversions=0;
integer last_conversion=-1;
integer samples=0;
integer waves=0;
integer spectrum_count=0;
reg block_started=1'b0;
reg block_done=1'b0;
reg previous_sample_valid=1'b0;
always@(posedge adc_convst)begin
if(rst27_n)begin
if(last_conversion>=0&&adc_cycle-last_conversion!=135)
$fatal(1,"INT FINAL: CONVST cambió la cadencia de 135 ciclos");
conversions=conversions+1;
last_conversion=adc_cycle;
end
end
always@(posedge clk27)begin
adc_cycle=adc_cycle+1;
if(rst27_n)begin
if(sample_valid)begin
if(previous_sample_valid||sample_signed!==adc_model.tone(samples))
$fatal(1,"INT FINAL: muestra %0d inválida o fuera de orden",samples);
samples=samples+1;
if(samples!=conversions)$fatal(1,"INT FINAL: pérdida o duplicación de muestra");
end
previous_sample_valid=sample_valid;
end
#1;
if(rst27_n)begin
if(adc_fault||processor_fault||display_fault)
$fatal(1,"INT FINAL: diagnóstico inesperado");
if(!block_done)begin
if(frame_begin)begin
if(block_started||frame_seq!==32'd0||samples<256)
$fatal(1,"INT FINAL: frente sin un primer bloque completo");
block_started=1'b1;
end
if(wave_valid)begin
if(!block_started||waves>=256||
wave_index!==waves[7:0]||wave_sample!==adc_model.tone(waves))
$fatal(1,"INT FINAL: dato de traza incorrecto en %0d",waves);
waves=waves+1;
end
if(spectrum_valid)begin
if(!block_started||waves!=256||spectrum_count>=129||
spectrum_index!==spectrum_count[7:0])
$fatal(1,"INT FINAL: magnitudes desordenadas o sin traza correspondiente");
if((spectrum_index==8'd4&&!(spectrum_mag>=18'd4080&&spectrum_mag<=18'd4112))||
(spectrum_index!=8'd4&&!(spectrum_mag<=18'd16)))
$fatal(1,"INT FINAL: magnitud inesperada en bin %0d: %0d",spectrum_index,spectrum_mag);
spectrum_count=spectrum_count+1;
end
if(frame_done)begin
if(!spectrum_valid||waves!=256||spectrum_count!=129)
$fatal(1,"INT FINAL: frame_done sin 256 muestras y 129 magnitudes");
block_done=1'b1;
end
end
end
end
function automatic[7:0]decode_pixel(input[9:0]code);
reg[7:0]payload,delta;
begin
payload=code[7:0]^{8{code[9]}};
delta=payload^(payload<<1);
if(!code[8])delta=delta^8'hfe;
decode_pixel=delta;
end
endfunction
function automatic[9:0]control_code(input[1:0]control);
case(control)
0:control_code=10'b1101010100;
1:control_code=10'b0010101011;
2:control_code=10'b0101010100;
3:control_code=10'b1010101011;
endcase
endfunction
task automatic advance_pixels(input integer count);
begin
repeat(count)begin@(posedge pix_clk);#1;end
end
endtask
reg[10:0]jump_x;
reg[9:0]jump_y;
task automatic jump_to_pixel(input[10:0]target_x,input[9:0]target_y);
begin
@(negedge pix_clk);
jump_x=target_x;
jump_y=target_y;
force dut.timing.x=jump_x;
force dut.timing.y=jump_y;
#1;
release dut.timing.x;
release dut.timing.y;
end
endtask
task automatic verify_video(
input[10:0]target_x,
input[9:0]target_y,
input[23:0]color,
input de,hs,vs
);
begin
jump_to_pixel(target_x,target_y);
advance_pixels(4);
if(rgb!==color||{video_de,video_hsync,video_vsync}!=={de,hs,vs})
$fatal(1,"INT FINAL: pixel %0d,%0d produjo %h en vez de %h",target_x,target_y,rgb,color);
advance_pixels(1);
if(de)begin
if({decode_pixel(tmds_red),decode_pixel(tmds_green),decode_pixel(tmds_blue)}!==color)
$fatal(1,"INT FINAL: TMDS no recupera RGB");
end else if(tmds_red!==control_code(0)||tmds_green!==control_code(0)||
tmds_blue!==control_code({vs,hs}))begin
$fatal(1,"INT FINAL: símbolo de control TMDS desalineado");
end
end
endtask
initial begin
repeat(5)@(negedge clk27);
rst27_n=1'b1;
@(negedge pix_base_clk);
rstpix_n=1'b1;
pixel_clock_running=1'b0;
wait(block_done);
repeat(3)@(negedge clk27);
@(negedge pix_base_clk);
pixel_clock_running=1'b1;
advance_pixels(6);
jump_to_pixel(11'd1649,10'd749);
advance_pixels(4);
if(!front_valid||front_seq!==32'd0||mode_fft)
$fatal(1,"INT FINAL: primer frente no publicado en la vista temporal");
verify_video(11'd129,10'd320,24'h00ff40,1,0,0);
@(negedge pix_clk);
key_s2=1'b1;
advance_pixels(16);
if(mode_fft)$fatal(1,"INT FINAL: S2 cambió antes del límite de cuadro");
jump_to_pixel(11'd1649,10'd749);
advance_pixels(4);
if(!mode_fft||!front_valid||front_seq!==32'd0)
$fatal(1,"INT FINAL: S2 no conmutó el mismo frente de ADC");
verify_video(11'd164,10'd610,24'h00d8ff,1,0,0);
verify_video(11'd1300,10'd10,24'd0,0,0,0);
verify_video(11'd1400,10'd10,24'd0,0,1,0);
verify_video(11'd1300,10'd725,24'd0,0,0,1);
verify_video(11'd1400,10'd725,24'd0,0,1,1);
@(negedge clk27);
rst27_n=1'b0;
rstpix_n=1'b0;
#1;
if(front_valid||mode_fft||rgb!==24'd0||video_de||video_hsync||video_vsync||
tmds_red!==control_code(0)||tmds_green!==control_code(0)||tmds_blue!==control_code(0))
$fatal(1,"INT FINAL: reset no limpia el estado de vídeo y TMDS");
$display("PASS: INTEGRACION FINAL FD73, %0d muestras, 256 de traza, bin 4/129 bins, S2, RGB y TMDS",samples);
done=1'b1;
if(STANDALONE)$finish;
end
initial begin
#3000000;
if(!done)$fatal(1,"INT FINAL: timeout de 3 ms");
end
endmodule
