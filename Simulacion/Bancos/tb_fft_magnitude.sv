`timescale 1ns/1ps
module tb_fft_magnitude;
localparam real CLOCK_NS=1000.0/27.0;
reg clk=1'b0;
always#(CLOCK_NS/2.0)clk=~clk;
reg rst_n=1'b0;
reg start=1'b0;
reg signed[17:0]in_re=0,in_im=0;
wire busy,done;
wire[17:0]magnitude;
reg[31:0]rng=32'h2026a18f;
integer cases_checked=0;
reg previous_done=1'b0;
reg[17:0]previous_magnitude=0;
fft_magnitude dut(
.clk(clk),.rst_n(rst_n),.start(start),
.in_re(in_re),.in_im(in_im),.busy(busy),
.done(done),.magnitude(magnitude)
);
function automatic[17:0]reference_root(
input logic signed[17:0]real_part,
input logic signed[17:0]imag_part
);
longint signed real64,imag64;
longint unsigned sum64,root64,trial64;
integer bit_index;
begin
real64=real_part;
imag64=imag_part;
sum64=real64*real64+imag64*imag64;
root64=0;
for(bit_index=17;bit_index>=0;bit_index=bit_index-1)begin
trial64=root64|(64'd1<<bit_index);
if(trial64*trial64<=sum64)
root64=trial64;
end
reference_root=root64[17:0];
end
endfunction
function automatic signed[17:0]random18;
begin
rng=rng*32'd1664525+32'd1013904223;
random18=$signed(rng[31:14]);
end
endfunction
always@(posedge clk)begin
#1;
if(!rst_n)begin
previous_done=1'b0;
previous_magnitude=0;
end else begin
if((done===1'bx)||(busy===1'bx))
$fatal(1,"MAG: control desconocido");
if(done&&previous_done)
$fatal(1,"MAG: done dura mas de un ciclo");
if(done&&busy)
$fatal(1,"MAG: done no desactiva busy");
if(!done&&magnitude!==previous_magnitude)
$fatal(1,"MAG: salida cambia fuera del flanco de resultado");
previous_done=done;
previous_magnitude=magnitude;
end
end
task automatic step_clock;
begin@(posedge clk);#1;end
endtask
task automatic reset_dut;
begin
@(negedge clk);rst_n=0;start=0;
repeat(3)@(negedge clk);
rst_n=1;
step_clock();
if(busy||done||magnitude!==18'd0)
$fatal(1,"MAG: reset no devuelve reposo y magnitud cero");
end
endtask
task automatic check_exact_result(
input logic signed[17:0]real_part,
input logic signed[17:0]imag_part
);
longint signed real64,imag64;
longint unsigned sum64,magnitude64,next64;
reg[17:0]expected;
begin
expected=reference_root(real_part,imag_part);
if(magnitude!==expected)
$fatal(1,"MAG caso %0d (%0d,%0d): got %0d, esperado %0d",
cases_checked,real_part,imag_part,magnitude,expected);
real64=real_part;
imag64=imag_part;
sum64=real64*real64+imag64*imag64;
magnitude64=$unsigned(magnitude);
next64=magnitude64+64'd1;
if((magnitude64*magnitude64>sum64)||
(next64*next64<=sum64))
$fatal(1,"MAG: incumple M^2 <= S < (M+1)^2");
cases_checked=cases_checked+1;
end
endtask
task automatic run_case(
input logic signed[17:0]real_part,
input logic signed[17:0]imag_part,
input bit inject_busy_start
);
integer elapsed;
reg[17:0]held_result;
begin
held_result=magnitude;
@(negedge clk);
if(busy)$fatal(1,"MAG: inicio de caso con DUT ocupado");
in_re=real_part;in_im=imag_part;start=1;
step_clock();
if(!busy||done||magnitude!==held_result)
$fatal(1,"MAG: captura incorrecta en C0");
@(negedge clk);
in_re=18'sh20000;in_im=18'sh1ffff;
start=inject_busy_start;
for(elapsed=1;elapsed<=20;elapsed=elapsed+1)begin
step_clock();
if(elapsed<20)begin
if(!busy||done||magnitude!==held_result)
$fatal(1,"MAG: latencia/retencion incorrecta en C%0d",elapsed);
end else begin
if(busy||!done)
$fatal(1,"MAG: resultado debe estar exactamente en C20");
check_exact_result(real_part,imag_part);
end
@(negedge clk);start=0;
end
held_result=magnitude;
repeat(3)begin
step_clock();
if(busy||done||magnitude!==held_result)
$fatal(1,"MAG: start ocupado quedo en cola o salida no retenida");
end
end
endtask
task automatic abort_operation(input integer completed_cycles);
integer elapsed;
begin
@(negedge clk);in_re=18'sh20000;in_im=18'sh20000;start=1;
step_clock();
if(!busy)$fatal(1,"MAG: no inicio operacion para abortar");
@(negedge clk);start=0;
for(elapsed=0;elapsed<completed_cycles;elapsed=elapsed+1)begin
step_clock();
if(!busy||done)$fatal(1,"MAG: termino antes del reset de prueba");
end
#3;rst_n=0;
#1;
if(busy||done||magnitude!==18'd0)
$fatal(1,"MAG: reset asincrono no aborta");
repeat(3)@(negedge clk);
rst_n=1;
repeat(23)begin
step_clock();
if(busy||done||magnitude!==18'd0)
$fatal(1,"MAG: resultado antiguo reaparecio despues del reset");
end
run_case(18'sd3,18'sd4,1'b1);
end
endtask
task automatic held_start_restarts;
integer elapsed;
begin
@(negedge clk);in_re=3;in_im=4;start=1;
step_clock();
@(negedge clk);in_re=5;in_im=12;
for(elapsed=1;elapsed<=20;elapsed=elapsed+1)begin
step_clock();
if(elapsed<20&&(!busy||done))
$fatal(1,"MAG: start retenido altero primera operacion");
end
if(busy||!done)$fatal(1,"MAG: primera operacion retenida no termino");
check_exact_result(18'sd3,18'sd4);
step_clock();
if(!busy||done)$fatal(1,"MAG: start alto en IDLE no inicia otra operacion");
@(negedge clk);start=0;
for(elapsed=1;elapsed<=20;elapsed=elapsed+1)begin
step_clock();
if(elapsed<20&&(!busy||done))
$fatal(1,"MAG: latencia de segunda operacion retenida incorrecta");
end
if(busy||!done)$fatal(1,"MAG: segunda operacion retenida no termino");
check_exact_result(18'sd5,18'sd12);
repeat(3)begin
step_clock();
if(busy||done)$fatal(1,"MAG: tercera operacion no solicitada");
end
end
endtask
integer index;
reg signed[17:0]random_re,random_im;
initial begin
$dumpfile("fft_magnitude.vcd");
$dumpvars(0,tb_fft_magnitude);
reset_dut();
run_case(0,0,0);
run_case(1,0,1);
run_case(-1,0,1);
run_case(0,1,1);
run_case(0,-1,1);
run_case(1,-1,1);
run_case(2,2,1);
run_case(3,4,1);
run_case(-3,-4,1);
run_case(-3,4,1);
run_case(511,32,1);
run_case(511,31,1);
run_case(512,0,1);
run_case(65535,1,1);
run_case(65536,0,1);
run_case(18'sh1ffff,0,1);
run_case(18'sh20000,0,1);
run_case(18'sh1ffff,18'sh1ffff,1);
run_case(18'sh20000,18'sh1ffff,1);
run_case(18'sh20000,18'sh20000,1);
if(magnitude!==18'd185363)
$fatal(1,"MAG: extremos negativos deben producir 185363");
for(index=0;index<256;index=index+1)begin
random_re=random18();random_im=random18();
run_case(random_re,random_im,1'b1);
end
abort_operation(0);
abort_operation(1);
abort_operation(9);
abort_operation(19);
held_start_restarts();
$display("PASS: MAGNITUD FFT, %0d casos exactos, propiedad floor, C20, signos, reset y start ocupado",cases_checked);
$finish;
end
initial begin#1000000;$fatal(1,"MAG: timeout global");end
endmodule
