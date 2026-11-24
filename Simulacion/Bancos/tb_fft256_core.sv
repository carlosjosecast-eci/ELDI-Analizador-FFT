`timescale 1ns/1ps
module tb_fft256_core;
localparam real PI=3.1415926535897932384626433832795;
localparam real CLOCK_NS=1000.0/27.0;
localparam real TOLERANCE_LSB=8.0;
localparam integer LIMIT_CYCLES=16384;
reg clk=0;
always#(CLOCK_NS/2.0)clk=!clk;
reg rst_n=0,in_valid=0,start=0,rd_en=0;
reg signed[15:0]in_sample=0;
reg[7:0]rd_addr=0;
wire in_ready,frame_loaded,busy,done,results_ready,rd_valid;
wire signed[17:0]rd_re,rd_im;
wire fault_latched;
wire[3:0]fault_code;
reg signed[15:0]proposed[0:255],accepted[0:255];
real expected_re[0:255],expected_im[0:255];
real max_error_re=0.0,max_error_im=0.0;
integer accepted_count=0,cycle_no=0,compute_start_cycle=0;
integer checked_frames=0,checked_bins=0;
reg previous_done=0;
reg expected_rd_valid;
fft256_core dut(
.clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_sample(in_sample),
.in_ready(in_ready),.start(start),.frame_loaded(frame_loaded),
.busy(busy),.done(done),.results_ready(results_ready),
.rd_en(rd_en),.rd_addr(rd_addr),.rd_re(rd_re),.rd_im(rd_im),
.rd_valid(rd_valid),.fault_latched(fault_latched),.fault_code(fault_code)
);
function automatic real abs_real(input real x);
abs_real=(x<0.0)?-x:x;
endfunction
function automatic integer quantize16(input real x);
integer q;
begin
q=(x>=0.0)?$rtoi(x+0.5):$rtoi(x-0.5);
if(q>32767)q=32767;
if(q<-32768)q=-32768;
quantize16=q;
end
endfunction
always@(posedge clk)begin
cycle_no=cycle_no+1;
expected_rd_valid=rst_n&&rd_en&&results_ready&&!busy&&
!(in_valid&&in_ready)&&!start;
if(!rst_n)accepted_count=0;
else if(in_valid&&in_ready)begin
if(accepted_count>=256)$fatal(1,"CORE: acepto mas de 256 muestras");
accepted[accepted_count]=in_sample;
accepted_count=accepted_count+1;
end
#1;
if(rst_n)begin
if(rd_valid!==expected_rd_valid)
$fatal(1,"CORE: rd_valid no cumple latencia/gating de un ciclo");
if(done&&previous_done)$fatal(1,"CORE: done dura mas de un ciclo");
if(done&&(busy||!results_ready))
$fatal(1,"CORE: done sin resultados estables");
if(busy&&results_ready)$fatal(1,"CORE: resultados visibles durante calculo");
previous_done=done;
end else previous_done=0;
end
task automatic step_clock;
begin@(posedge clk);#1;end
endtask
task automatic reset_dut;
begin
@(negedge clk);rst_n=0;in_valid=0;start=0;rd_en=0;
repeat(3)@(negedge clk);
rst_n=1;
step_clock();
if(busy||done||frame_loaded||results_ready||fault_latched||!in_ready)
$fatal(1,"CORE: estado inicial incorrecto");
end
endtask
task automatic make_frame(input integer family);
integer n,value;
reg[31:0]state;
real x;
begin
state=32'h5eed2026;
for(n=0;n<256;n=n+1)begin
x=0.0;
case(family)
0:value=0;
1:value=32767;
2:value=-32768;
3:value=-1;
4:value=(n==0)?32767:0;
5:value=(n==37)?-32768:0;
6:begin x=12000.0*$sin(2.0*PI*7.0*n/256.0);value=quantize16(x);end
7:begin x=12000.0*$cos(2.0*PI*11.0*n/256.0);value=quantize16(x);end
8:begin
x=8000.0*$sin(2.0*PI*5.0*n/256.0)+6000.0*$cos(2.0*PI*19.0*n/256.0);
value=quantize16(x);
end
9:begin x=15000.0*$sin(2.0*PI*17.25*n/256.0);value=quantize16(x);end
10:value=(n%2==0)?32767:-32768;
11:value=(n%2==0)?-32768:32767;
12:begin
state=state*32'd1664525+32'd1013904223;
value=$signed(state[31:16]);
end
13:case(n%4)
0:value=0;1:value=32767;2:value=-32768;3:value=-1;
endcase
default:value=0;
endcase
proposed[n]=value;
end
end
endtask
task automatic load_frame;
integer n,gap;
begin
@(negedge clk);accepted_count=0;in_valid=0;start=0;rd_en=0;
for(n=0;n<256;n=n+1)begin
@(negedge clk);
if(!in_ready)$fatal(1,"CORE: backpressure inesperada al cargar %0d",n);
in_valid=1;in_sample=proposed[n];rd_en=(n==0);
step_clock();
if(accepted_count!=n+1)$fatal(1,"CORE: handshake perdido en %0d",n);
if(results_ready)$fatal(1,"CORE: nueva entrada no invalido resultado anterior");
if(n<255&&frame_loaded)$fatal(1,"CORE: frame_loaded temprano");
if(n%5==2)begin
@(negedge clk);in_valid=0;rd_en=0;
for(gap=0;gap<(n%3)+1;gap=gap+1)step_clock();
end
end
@(negedge clk);in_valid=0;rd_en=0;
if(!frame_loaded||in_ready||accepted_count!=256)
$fatal(1,"CORE: bloque completo/ready incorrecto");
in_valid=1;in_sample=16'h5a5a;rd_en=1;
repeat(2)step_clock();
if(accepted_count!=256||in_ready||fault_latched)
$fatal(1,"CORE: entrada extra altero bloque completo");
@(negedge clk);in_valid=0;rd_en=0;
end
endtask
task automatic direct_dft;
integer k,n,sample_value;
real sr,si,theta;
begin
for(k=0;k<256;k=k+1)begin
sr=0.0;si=0.0;
for(n=0;n<256;n=n+1)begin
sample_value=$signed(accepted[n]);
theta=2.0*PI*k*n/256.0;
sr=sr+sample_value*$cos(theta);
si=si-sample_value*$sin(theta);
end
expected_re[k]=sr/256.0;
expected_im[k]=si/256.0;
end
end
endtask
task automatic begin_fft;
begin
@(negedge clk);start=1;rd_en=1;
step_clock();compute_start_cycle=cycle_no;
if(!busy||frame_loaded||results_ready||fault_latched)
$fatal(1,"CORE: start valido no inicio el calculo");
@(negedge clk);start=0;
in_valid=1;in_sample=16'h7fff;
repeat(4)begin
step_clock();
if(in_ready||rd_valid||accepted_count!=256||fault_latched)
$fatal(1,"CORE: entrada/lectura durante busy no fue ignorada");
end
@(negedge clk);in_valid=0;rd_en=0;
end
endtask
task automatic finish_fft;
integer latency;
begin
while(!done&&cycle_no-compute_start_cycle<=LIMIT_CYCLES)begin
step_clock();
if(fault_latched)$fatal(1,"CORE: fault inesperado %0d",fault_code);
if(!busy&&!done)$fatal(1,"CORE: paro sin done");
end
latency=cycle_no-compute_start_cycle;
if(!done||latency>LIMIT_CYCLES)
$fatal(1,"CORE: latencia %0d supera %0d ciclos",latency,LIMIT_CYCLES);
if(!results_ready||busy||frame_loaded)
$fatal(1,"CORE: banderas finales incorrectas");
$display("CORE: calculo termino en %0d ciclos",latency);
end
endtask
task automatic check_results(input integer family);
integer k,got_re,got_im;
real er,ei;
begin
for(k=0;k<256;k=k+1)begin
@(negedge clk);rd_en=1;rd_addr=k;
step_clock();
if(!rd_valid||(^rd_re===1'bx)||(^rd_im===1'bx))
$fatal(1,"CORE: resultado desconocido/invalido bin %0d",k);
got_re=$signed(rd_re);got_im=$signed(rd_im);
er=abs_real(got_re-expected_re[k]);ei=abs_real(got_im-expected_im[k]);
if(er>max_error_re)max_error_re=er;
if(ei>max_error_im)max_error_im=ei;
if(er>TOLERANCE_LSB||ei>TOLERANCE_LSB)
$fatal(1,"CORE familia%0d bin%0d: got=(%0d,%0d), DFT/N=(%0.6f,%0.6f), error=(%0.6f,%0.6f)",
family,k,got_re,got_im,expected_re[k],expected_im[k],er,ei);
checked_bins=checked_bins+1;
end
@(negedge clk);rd_en=0;
repeat(3)begin
step_clock();
if(done||!results_ready||busy||rd_valid)
$fatal(1,"CORE: resultado no permanece disponible o done largo");
end
checked_frames=checked_frames+1;
$display("PASS: CORE familia %0d, 256 bins complejos en orden natural",family);
end
endtask
task automatic pulse_start;
begin
@(negedge clk);start=1;
step_clock();
@(negedge clk);start=0;
end
endtask
task automatic expect_fault(input[3:0]code);
integer elapsed;
begin
elapsed=0;
while(!fault_latched&&elapsed<5)begin step_clock();elapsed=elapsed+1;end
if(!fault_latched||fault_code!==code)
$fatal(1,"CORE: fault %0d esperado, got %0d",code,fault_code);
@(negedge clk);in_valid=1;in_sample=123;rd_en=1;
repeat(10)begin
step_clock();
if(!fault_latched||fault_code!==code||in_ready||busy||done||results_ready||rd_valid)
$fatal(1,"CORE: fault no queda retenido/abortado hasta reset");
end
@(negedge clk);in_valid=0;rd_en=0;
end
endtask
integer family,n;
initial begin
$dumpfile("fft256_core.vcd");$dumpvars(1,tb_fft256_core);
reset_dut();
@(negedge clk);rd_en=1;
repeat(3)step_clock();
@(negedge clk);rd_en=0;
for(family=0;family<14;family=family+1)begin
make_frame(family);load_frame();direct_dft();begin_fft();
finish_fft();check_results(family);
end
reset_dut();
for(n=0;n<23;n=n+1)begin
@(negedge clk);in_valid=1;in_sample=n*173;
step_clock();
end
reset_dut();
if(accepted_count!=0)$fatal(1,"CORE: reset no borro carga parcial");
pulse_start();expect_fault(4'd1);
reset_dut();
for(n=0;n<255;n=n+1)begin
@(negedge clk);in_valid=1;in_sample=n-128;
step_clock();
end
@(negedge clk);in_sample=32767;start=1;
step_clock();
@(negedge clk);start=0;in_valid=0;
expect_fault(4'd1);
reset_dut();
make_frame(7);load_frame();begin_fft();
pulse_start();expect_fault(4'd2);
reset_dut();
make_frame(12);load_frame();begin_fft();
repeat(20)step_clock();
reset_dut();
repeat(20)begin
step_clock();
if(busy||done||results_ready||fault_latched)
$fatal(1,"CORE: calculo anterior reaparecio tras reset");
end
make_frame(0);load_frame();direct_dft();begin_fft();finish_fft();check_results(0);
$display("PASS: FFT256, %0d bloques/%0d bins; max error Re=%0.6f Im=%0.6f LSB; controles y recuperacion",
checked_frames,checked_bins,max_error_re,max_error_im);
$finish;
end
initial begin#20000000;$fatal(1,"CORE: timeout global");end
endmodule
