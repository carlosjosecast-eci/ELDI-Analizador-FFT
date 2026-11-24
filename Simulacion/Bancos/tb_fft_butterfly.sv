`timescale 1ns/1ps
module tb_fft_butterfly;
localparam real CLOCK_NS=1000.0/27.0;
reg clk=0;
always#(CLOCK_NS/2.0)clk=!clk;
reg rst_n=0,start=0;
reg signed[17:0]a_re=0,a_im=0,b_re=0,b_im=0,w_re=0,w_im=0;
wire busy,done;
wire signed[17:0]y0_re,y0_im,y1_re,y1_im;
integer cases_checked=0;
reg[31:0]rng=32'h62024a17;
fft_butterfly dut(
.clk(clk),.rst_n(rst_n),.start(start),.a_re(a_re),.a_im(a_im),
.b_re(b_re),.b_im(b_im),.w_re(w_re),.w_im(w_im),
.busy(busy),.done(done),.y0_re(y0_re),.y0_im(y0_im),
.y1_re(y1_re),.y1_im(y1_im)
);
function automatic signed[17:0]round_sat(input longint signed n);
longint signed q;
begin
if(n>=0)q=(n+64'sd65536)/64'sd131072;
else q=-((-n+64'sd65536)/64'sd131072);
if(q>131071)round_sat=18'sd131071;
else if(q<-131072)round_sat=-18'sd131072;
else round_sat=q;
end
endfunction
function automatic signed[17:0]random18;
begin
rng=rng*32'd1664525+32'd1013904223;
random18=$signed(rng[31:14]);
end
endfunction
task automatic reset_dut;
begin
@(negedge clk);rst_n=0;start=0;
repeat(3)@(negedge clk);
rst_n=1;
@(posedge clk);#1;
if(busy||done)$fatal(1,"BF: reset no devuelve reposo");
end
endtask
task automatic run_case(
input logic signed[17:0]ar,ai,br,bi,wr,wi,
input bit inject_busy_start
);
longint signed ar64,ai64,br64,bi64,wr64,wi64,tr,ti;
reg signed[17:0]e0r,e0i,e1r,e1i;
integer elapsed;
begin
ar64=ar;ai64=ai;br64=br;bi64=bi;wr64=wr;wi64=wi;
tr=br64*wr64-bi64*wi64;
ti=br64*wi64+bi64*wr64;
e0r=round_sat(ar64*65536+tr);e0i=round_sat(ai64*65536+ti);
e1r=round_sat(ar64*65536-tr);e1i=round_sat(ai64*65536-ti);
@(negedge clk);
if(busy)$fatal(1,"BF: intento de caso con DUT ocupado");
a_re=ar;a_im=ai;b_re=br;b_im=bi;w_re=wr;w_im=wi;start=1;
@(posedge clk);#1;
if(!busy||done)$fatal(1,"BF: start no capturado en C0");
@(negedge clk);
a_re=18'sd131071;a_im=-18'sd131072;
b_re=-18'sd131072;b_im=18'sd131071;
w_re=18'sd12345;w_im=-18'sd54321;
start=inject_busy_start;
for(elapsed=1;elapsed<=3;elapsed=elapsed+1)begin
@(posedge clk);#1;
if(elapsed<3&&(!busy||done))
$fatal(1,"BF: latencia incorrecta en C%0d",elapsed);
if(elapsed==3)begin
if(busy||!done)$fatal(1,"BF: resultado debe estar en C3");
if(y0_re!==e0r||y0_im!==e0i||y1_re!==e1r||y1_im!==e1i)
$fatal(1,"BF caso %0d: got (%0d,%0d),(%0d,%0d); esperado (%0d,%0d),(%0d,%0d)",
cases_checked,y0_re,y0_im,y1_re,y1_im,e0r,e0i,e1r,e1i);
end
@(negedge clk);start=0;
end
repeat(3)begin
@(posedge clk);#1;
if(done||busy)$fatal(1,"BF: done largo o start ocupado quedo en cola");
end
cases_checked=cases_checked+1;
end
endtask
integer n;
reg signed[17:0]ra,ia,rb,ib,rw,iw;
initial begin
$dumpfile("fft_butterfly.vcd");$dumpvars(0,tb_fft_butterfly);
reset_dut();
run_case(0,0,0,0,65536,0,0);
run_case(12003,-7001,-23001,11007,65536,0,1);
run_case(12003,-7001,-23001,11007,-65536,0,1);
run_case(12003,-7001,-23001,11007,0,65536,1);
run_case(12003,-7001,-23001,11007,0,-65536,1);
run_case(-32768,32767,23111,-17003,46341,-46341,1);
run_case(1,-1,0,0,0,0,0);
run_case(0,0,1,-1,65536,0,0);
run_case(0,0,-1,1,65536,0,0);
run_case(3,-3,0,0,0,0,0);
run_case(1,-1,1,-1,1,0,0);
run_case(131071,131071,131071,-131072,131071,-131072,1);
run_case(-131072,-131072,-131072,131071,131071,-131072,1);
run_case(131071,-131072,-131072,131071,-131072,131071,1);
for(n=0;n<128;n=n+1)begin
ra=random18();ia=random18();rb=random18();ib=random18();
rw=random18();iw=random18();
run_case(ra,ia,rb,ib,rw,iw,1);
end
@(negedge clk);start=1;a_re=123;b_re=456;w_re=65536;
@(posedge clk);#1;
if(!busy)$fatal(1,"BF: no inicio caso para reset ocupado");
@(negedge clk);start=0;rst_n=0;
#1;
if(busy||done)$fatal(1,"BF: reset ocupado no aborta");
repeat(3)@(negedge clk);
rst_n=1;
repeat(5)begin
@(posedge clk);#1;
if(busy||done)$fatal(1,"BF: resultado viejo reaparecio tras reset");
end
run_case(-32768,0,32767,0,65536,0,1);
$display("PASS: MARIPOSA FFT, %0d casos bit exactos, latencia C3, reset y start ocupado",cases_checked);
$finish;
end
initial begin#1000000;$fatal(1,"BF: timeout global");end
endmodule
