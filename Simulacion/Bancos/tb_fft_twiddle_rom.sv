`timescale 1ns/1ps
module tb_fft_twiddle_rom;
reg clk=1'b0;
always#5clk=~clk;
reg en=1'b0;
reg[6:0]addr=7'd0;
wire signed[17:0]w_re,w_im;
integer index;
integer expected_re,expected_im;
integer previous_re,previous_im;
integer checks=0;
real angle;
localparam real PI=3.14159265358979323846;
fft_twiddle_rom dut(
.clk(clk),.en(en),.addr(addr),.w_re(w_re),.w_im(w_im)
);
function automatic integer nearest_away(input real value);
begin
if(value>=0.0)
nearest_away=$rtoi(value+0.5);
else
nearest_away=-$rtoi(-value+0.5);
end
endfunction
initial begin
repeat(2)@(negedge clk);
for(index=0;index<128;index=index+1)begin
@(negedge clk);
en=1'b1;
addr=index[6:0];
#1;
if(index>0&&
($signed(w_re)!==previous_re||$signed(w_im)!==previous_im))
$fatal(1,"La ROM cambio antes del flanco de lectura: indice %0d",index);
angle=2.0*PI*index/256.0;
expected_re=nearest_away(65536.0*$cos(angle));
expected_im=nearest_away(-65536.0*$sin(angle));
@(posedge clk);
#1;
if($signed(w_re)!==expected_re||$signed(w_im)!==expected_im)
$fatal(1,"W[%0d]=(%0d,%0d), esperado=(%0d,%0d)",
index,$signed(w_re),$signed(w_im),expected_re,expected_im);
checks=checks+1;
previous_re=expected_re;
previous_im=expected_im;
@(negedge clk);
en=1'b0;
addr=7'd127-index[6:0];
repeat(2)begin
@(posedge clk);
#1;
if($signed(w_re)!==previous_re||$signed(w_im)!==previous_im)
$fatal(1,"La ROM no retuvo coeficiente con en=0: indice %0d",index);
checks=checks+1;
end
end
$display("PASS: ROM FFT256, 128 coeficientes y retencion sincrona, %0d comprobaciones",checks);
$finish;
end
initial begin
#100000;
$fatal(1,"Timeout ROM FFT256");
end
endmodule
