`timescale 1ns/1ps
module tb_display_buffer;
localparam real WR_PERIOD_NS=1000.0/27.0;
localparam real PIX_PERIOD_NS=1000.0/74.25;
reg wr_clk=0,pix_clk=0;
always#(WR_PERIOD_NS/2.0)wr_clk=~wr_clk;
initial begin
#2.731;
forever#(PIX_PERIOD_NS/2.0)pix_clk=~pix_clk;
end
reg wr_rst_n=0,pix_rst_n=0;
reg frame_start=0;
reg frame_begin=0,wave_valid=0,spectrum_valid=0,frame_done=0;
reg[31:0]frame_seq=0;
reg[7:0]wave_index=0,spectrum_index=0;
reg signed[15:0]wave_sample=0;
reg[17:0]spectrum_mag=0;
wire wr_busy,wr_fault_latched,front_valid;
wire[31:0]front_seq;
reg rd_en=0;
reg[7:0]rd_wave_addr=0,rd_spectrum_addr=0;
wire rd_valid;
wire signed[15:0]rd_wave_prev,rd_wave_sample;
wire[17:0]rd_spectrum_mag;
integer checked_reads=0,checked_frames=0,observed_swaps=0;
reg previous_front_valid=0;
reg[31:0]previous_front_seq=0;
reg previous_fault=0;
reg expected_rd_valid;
reg boundary_at_edge;
display_buffer dut(
.wr_clk(wr_clk),.wr_rst_n(wr_rst_n),.pix_clk(pix_clk),
.pix_rst_n(pix_rst_n),.frame_start(frame_start),
.frame_begin(frame_begin),.frame_seq(frame_seq),
.wave_valid(wave_valid),.wave_index(wave_index),.wave_sample(wave_sample),
.spectrum_valid(spectrum_valid),.spectrum_index(spectrum_index),
.spectrum_mag(spectrum_mag),.frame_done(frame_done),
.wr_busy(wr_busy),.wr_fault_latched(wr_fault_latched),
.front_valid(front_valid),.front_seq(front_seq),
.rd_en(rd_en),.rd_wave_addr(rd_wave_addr),.rd_spectrum_addr(rd_spectrum_addr),
.rd_valid(rd_valid),.rd_wave_prev(rd_wave_prev),
.rd_wave_sample(rd_wave_sample),.rd_spectrum_mag(rd_spectrum_mag)
);
function automatic signed[15:0]expected_wave(input integer identity,index);
begin
case(index)
0:expected_wave=16'h8000;
1:expected_wave=16'h7fff;
254:expected_wave=16'hffff;
255:expected_wave=16'h0001^identity;
default:expected_wave=(index*257)^(identity*16'h1337)^16'ha55a;
endcase
end
endfunction
function automatic[17:0]expected_spectrum(input integer identity,index);
begin
if(index>128)
expected_spectrum=18'd0;
else if(index==0)
expected_spectrum=18'd185363+identity;
else if(index==128)
expected_spectrum=18'h3ffff-identity;
else
expected_spectrum=(identity*17777+index*1387)&18'h3ffff;
end
endfunction
always@(posedge pix_clk)begin
expected_rd_valid=pix_rst_n&&rd_en&&front_valid;
boundary_at_edge=frame_start;
#1;
if(!pix_rst_n)begin
previous_front_valid=0;
previous_front_seq=0;
end else begin
if(rd_valid!==expected_rd_valid)
$fatal(1,"DISPLAY: rd_valid no cumple latencia de un flanco");
if((front_valid!==previous_front_valid)||
(front_seq!==previous_front_seq))begin
if(!boundary_at_edge)
$fatal(1,"DISPLAY: frente cambio fuera de frame_start");
if(!front_valid)
$fatal(1,"DISPLAY: frente valido desaparecio sin reset");
observed_swaps=observed_swaps+1;
end
previous_front_valid=front_valid;
previous_front_seq=front_seq;
end
end
always@(posedge wr_clk)begin
#1;
if(!wr_rst_n)previous_fault=0;
else begin
if(previous_fault&&!wr_fault_latched)
$fatal(1,"DISPLAY: fallo no retenido hasta reset");
if(wr_fault_latched&&!wr_busy)
$fatal(1,"DISPLAY: fallo no indica escritor indisponible");
previous_fault=wr_fault_latched;
end
end
task automatic wr_step;
begin@(posedge wr_clk);#1;end
endtask
task automatic pix_step;
begin@(posedge pix_clk);#1;end
endtask
task automatic reset_both;
begin
@(negedge wr_clk);
wr_rst_n=0;pix_rst_n=0;
frame_begin=0;wave_valid=0;spectrum_valid=0;frame_done=0;
frame_start=0;rd_en=0;
repeat(5)@(negedge wr_clk);
wr_rst_n=1;
@(negedge pix_clk);pix_rst_n=1;
repeat(5)wr_step();
repeat(5)pix_step();
if(wr_busy||wr_fault_latched||front_valid||rd_valid)
$fatal(1,"DISPLAY: reset coordinado no devuelve estado inicial");
end
endtask
task automatic wait_writer_free;
integer elapsed;
begin
elapsed=0;
while(wr_busy&&elapsed<20)begin wr_step();elapsed=elapsed+1;end
if(wr_busy||wr_fault_latched)
$fatal(1,"DISPLAY: ACK no libero el banco anterior");
end
endtask
task automatic drive_frame(
input integer identity,
input bit wave0_with_begin,
input bit spectrum0_with_last_wave
);
integer index;
begin
@(negedge wr_clk);
frame_begin=1;frame_seq=identity;
wave_valid=wave0_with_begin;wave_index=0;
wave_sample=expected_wave(identity,0);
spectrum_valid=0;frame_done=0;
wr_step();
@(negedge wr_clk);frame_begin=0;
for(index=wave0_with_begin?1:0;index<256;index=index+1)begin
wave_valid=1;wave_index=index;
wave_sample=expected_wave(identity,index);
spectrum_valid=spectrum0_with_last_wave&&(index==255);
spectrum_index=0;spectrum_mag=expected_spectrum(identity,0);
wr_step();
@(negedge wr_clk);
end
wave_valid=0;
for(index=spectrum0_with_last_wave?1:0;index<=128;index=index+1)begin
spectrum_valid=1;spectrum_index=index;
spectrum_mag=expected_spectrum(identity,index);
frame_done=(index==128);
wr_step();
@(negedge wr_clk);
end
spectrum_valid=0;frame_done=0;
end
endtask
task automatic swap_at_boundary(input integer identity);
begin
repeat(6)pix_step();
@(negedge pix_clk);frame_start=1;
pix_step();
if(!front_valid||front_seq!==identity)
$fatal(1,"DISPLAY: swap esperado seq%0d, obtenido valid%0d seq%0d",
identity,front_valid,front_seq);
@(negedge pix_clk);frame_start=0;
end
endtask
task automatic check_read_data(input integer identity,wave_address,spectrum_address);
reg signed[15:0]expected_previous;
begin
expected_previous=expected_wave(identity,(wave_address==0)?0:wave_address-1);
if(!rd_valid||(rd_wave_prev!==expected_previous)||
(rd_wave_sample!==expected_wave(identity,wave_address))||
(rd_spectrum_mag!==expected_spectrum(identity,spectrum_address)))
$fatal(1,"DISPLAY: datos seq%0d wave%0d spec%0d: prev=%h sample=%h mag=%h",
identity,wave_address,spectrum_address,
rd_wave_prev,rd_wave_sample,rd_spectrum_mag);
checked_reads=checked_reads+1;
end
endtask
task automatic read_frame(input integer identity);
integer index;
reg[63:0]observed_hash,expected_hash,expected_word;
reg[15:0]previous_word,sample_word;
reg[17:0]magnitude_word;
begin
observed_hash=64'hcbf29ce484222325;
expected_hash=64'hcbf29ce484222325;
for(index=0;index<256;index=index+1)begin
@(negedge pix_clk);
rd_en=1;rd_wave_addr=index;rd_spectrum_addr=index;
pix_step();
if(!front_valid||front_seq!==identity)
$fatal(1,"DISPLAY: identidad del frente cambio durante lectura");
check_read_data(identity,index,index);
observed_hash=(observed_hash*64'd1099511628211)^
{14'd0,rd_wave_prev,rd_wave_sample,rd_spectrum_mag};
previous_word=expected_wave(identity,(index==0)?0:index-1);
sample_word=expected_wave(identity,index);
magnitude_word=expected_spectrum(identity,index);
expected_word={14'd0,previous_word,sample_word,magnitude_word};
expected_hash=(expected_hash*64'd1099511628211)^expected_word;
end
@(negedge pix_clk);rd_en=0;
pix_step();
if(rd_valid||observed_hash!==expected_hash)
$fatal(1,"DISPLAY: hash o fin de lectura incorrecto");
checked_frames=checked_frames+1;
$display("DISPLAY: seq%0d hash=%h,256pares wave y espectro con ceros129..255",identity,observed_hash);
end
endtask
task automatic begin_only(input integer identity);
begin
@(negedge wr_clk);frame_begin=1;frame_seq=identity;
wave_valid=0;spectrum_valid=0;frame_done=0;
wr_step();
@(negedge wr_clk);frame_begin=0;
end
endtask
task automatic expect_fault;
begin
wr_step();
if(!wr_fault_latched||!wr_busy)
$fatal(1,"DISPLAY: protocolo mal formado no produjo fallo");
repeat(8)wr_step();
if(!wr_fault_latched)
$fatal(1,"DISPLAY: fallo no quedo retenido");
end
endtask
integer index;
initial begin
$dumpfile("display_buffer.vcd");$dumpvars(1,tb_display_buffer);
reset_both();
@(negedge pix_clk);rd_en=1;rd_wave_addr=255;rd_spectrum_addr=255;
repeat(4)begin pix_step();if(rd_valid)$fatal(1,"DISPLAY: lectura antes del primer frente");end
@(negedge pix_clk);rd_en=0;
drive_frame(1,1,1);
if(!wr_busy||wr_fault_latched||front_valid)
$fatal(1,"DISPLAY: commit no espero el primer limite de imagen");
drive_frame(2,0,0);
repeat(6)pix_step();
if(!wr_busy||wr_fault_latched||front_valid)
$fatal(1,"DISPLAY: cuadro ignorado altero pendiente o frente");
swap_at_boundary(1);wait_writer_free();read_frame(1);
fork
drive_frame(3,0,0);
read_frame(1);
join
if(wr_fault_latched||!wr_busy||front_seq!==32'd1)
$fatal(1,"DISPLAY: escritura trasera cambio el frente o perdio commit");
fork
drive_frame(4,0,0);
begin
repeat(40)wr_step();
swap_at_boundary(3);wait_writer_free();read_frame(3);
end
join
if(wr_fault_latched||wr_busy||front_seq!==32'd3)
$fatal(1,"DISPLAY: se acepto parte de un cuadro descartado durante ACK");
fork
drive_frame(5,0,0);
read_frame(3);
join
repeat(6)pix_step();
@(negedge pix_clk);
rd_en=1;rd_wave_addr=0;rd_spectrum_addr=128;frame_start=1;
pix_step();
if(!front_valid||front_seq!==32'd5)
$fatal(1,"DISPLAY: lectura/swap simultaneo no publico seq5");
check_read_data(3,0,128);
@(negedge pix_clk);rd_en=0;frame_start=0;
wait_writer_free();read_frame(5);
begin_only(6);
wave_valid=1;wave_index=0;wave_sample=expected_wave(6,0);
wr_step();
@(negedge wr_clk);wave_index=2;wave_sample=expected_wave(6,2);
wr_step();
@(negedge wr_clk);wave_valid=0;
expect_fault();
swap_at_boundary(5);read_frame(5);
begin_only(7);expect_fault();
if(front_seq!==32'd5)$fatal(1,"DISPLAY: fallo altero metadatos visibles");
reset_both();
begin_only(7);
wave_valid=1;wave_index=0;wave_sample=expected_wave(7,0);frame_done=1;
wr_step();
@(negedge wr_clk);wave_valid=0;frame_done=0;
expect_fault();
@(negedge pix_clk);frame_start=1;pix_step();
if(front_valid)$fatal(1,"DISPLAY: fin prematuro publico cuadro");
@(negedge pix_clk);frame_start=0;
reset_both();
begin_only(8);
begin_only(9);
expect_fault();
reset_both();
begin_only(10);
for(index=0;index<256;index=index+1)begin
wave_valid=1;wave_index=index;wave_sample=expected_wave(10,index);
wr_step();@(negedge wr_clk);
end
wave_valid=0;spectrum_valid=1;spectrum_index=1;
spectrum_mag=expected_spectrum(10,1);
wr_step();@(negedge wr_clk);spectrum_valid=0;
expect_fault();
reset_both();begin_only(10);
wave_valid=1;wave_index=0;wave_sample=expected_wave(10,0);
wr_step();@(negedge wr_clk);wave_valid=0;
reset_both();
@(negedge pix_clk);frame_start=1;pix_step();
if(front_valid)$fatal(1,"DISPLAY: reaparecio cuadro parcial previo al reset");
@(negedge pix_clk);frame_start=0;
drive_frame(11,0,0);swap_at_boundary(11);wait_writer_free();read_frame(11);
drive_frame(12,0,0);
if(!wr_busy)$fatal(1,"DISPLAY: falta publicacion pendiente para reset");
reset_both();
@(negedge pix_clk);frame_start=1;pix_step();
if(front_valid)$fatal(1,"DISPLAY: reaparecio request previo al reset");
@(negedge pix_clk);frame_start=0;
drive_frame(13,1,1);swap_at_boundary(13);wait_writer_free();read_frame(13);
if(observed_swaps!=5)
$fatal(1,"DISPLAY: cantidad de intercambios incorrecta: %0d",observed_swaps);
$display("PASS: DISPLAY_BUFFER, %0d lecturas exactas/%0d verificaciones completas,5swaps,CDC,descartes,protocolo y reset",checked_reads,checked_frames);
$finish;
end
initial begin#2000000;$fatal(1,"DISPLAY: timeout global");end
endmodule
