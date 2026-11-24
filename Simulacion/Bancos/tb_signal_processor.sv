`timescale 1ns/1ps
module tb_signal_processor;
localparam real CLOCK_NS=1000.0/27.0;
localparam real PI=3.1415926535897932384626433832795;
localparam real MAG_TOLERANCE_LSB=9.0;
localparam integer FRAME_DEADLINE=20000;
localparam integer MODE_OFF=0,MODE_SUCCESS=1,MODE_ABORT=2,MODE_OVERLOAD=3;
reg clk=0;
always#(CLOCK_NS/2.0)clk=!clk;
reg rst_n=0,sample_valid=0;
reg signed[15:0]sample_signed=0;
wire frame_begin;
wire[31:0]frame_seq;
wire wave_valid;
wire[7:0]wave_index;
wire signed[15:0]wave_sample;
wire spectrum_valid;
wire[7:0]spectrum_index;
wire[17:0]spectrum_mag;
wire frame_done,busy,fault_latched;
wire[3:0]fault_code;
signal_processor dut(
.clk(clk),.rst_n(rst_n),.sample_valid(sample_valid),
.sample_signed(sample_signed),.frame_begin(frame_begin),
.frame_seq(frame_seq),.wave_valid(wave_valid),.wave_index(wave_index),
.wave_sample(wave_sample),.spectrum_valid(spectrum_valid),
.spectrum_index(spectrum_index),.spectrum_mag(spectrum_mag),
.frame_done(frame_done),.busy(busy),.fault_latched(fault_latched),
.fault_code(fault_code)
);
reg signed[15:0]actual_input[0:2][0:255];
real ideal_magnitude[0:2][0:128];
integer mode=MODE_OFF,frame_limit=3;
integer cycle_no=0,physical_count=0,last_sample_cycle=-1;
integer active_frame=-1,frame_start_cycle=0,completed_frames=0;
integer wave_count=0,spectrum_count=0,phase_waves=0,phase_bins=0;
integer successful_frames_total=0,maximum_frame_cycles=0;
real maximum_magnitude_error=0.0;
reg check_cadence=0,previous_begin=0,previous_done=0;
integer input_frame,input_index;
integer got_magnitude,latency;
real magnitude_error;
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
function automatic signed[15:0]source_word(input integer family,n);
begin
case(family%3)
0:source_word=16'sd12000;
1:source_word=quantize16(8000.0*$cos(2.0*PI*4.0*n/256.0));
2:source_word=quantize16(16000.0*$sin(2.0*PI*9.0*n/256.0));
endcase
end
endfunction
task automatic build_dft_magnitude(input integer frame_number);
integer k,n,x;
real r,i,theta;
begin
for(k=0;k<=128;k=k+1)begin
r=0.0;i=0.0;
for(n=0;n<256;n=n+1)begin
x=$signed(actual_input[frame_number][n]);
theta=2.0*PI*k*n/256.0;
r=r+x*$cos(theta);
i=i-x*$sin(theta);
end
r=r/256.0;i=i/256.0;
ideal_magnitude[frame_number][k]=$sqrt(r*r+i*i);
end
end
endtask
always@(posedge clk)begin
cycle_no=cycle_no+1;
if(!rst_n)begin
physical_count=0;
last_sample_cycle=-1;
active_frame=-1;
completed_frames=0;
wave_count=0;spectrum_count=0;phase_waves=0;phase_bins=0;
previous_begin=0;previous_done=0;
end else if(sample_valid)begin
if(check_cadence&&last_sample_cycle>=0&&cycle_no-last_sample_cycle!=135)
$fatal(1,"PROCESSOR: entrada no mantiene 135 ciclos; intervalo=%0d",cycle_no-last_sample_cycle);
last_sample_cycle=cycle_no;
if(mode==MODE_SUCCESS)begin
input_frame=physical_count/256;
input_index=physical_count%256;
if(input_frame>=frame_limit||input_frame>2)
$fatal(1,"PROCESSOR: mas muestras que los bloques esperados");
actual_input[input_frame][input_index]=sample_signed;
if(input_index==255)build_dft_magnitude(input_frame);
end
physical_count=physical_count+1;
end
#1;
if(rst_n)begin
if(frame_begin&&previous_begin)
$fatal(1,"PROCESSOR: frame_begin dura mas de un ciclo");
if(frame_done&&previous_done)
$fatal(1,"PROCESSOR: frame_done dura mas de un ciclo");
previous_begin=frame_begin;
previous_done=frame_done;
if(fault_latched&&(frame_begin||wave_valid||spectrum_valid||frame_done))
$fatal(1,"PROCESSOR: publico strobes despues de un fault retenido");
if(mode==MODE_OVERLOAD&&frame_done)
$fatal(1,"PROCESSOR: sobrecarga publico un bloque incompleto");
if(mode==MODE_SUCCESS)begin
if(fault_latched)$fatal(1,"PROCESSOR: fallo inesperado %0d",fault_code);
if(frame_begin)begin
if(active_frame>=0)$fatal(1,"PROCESSOR: superposicion de bloques publicados");
if(completed_frames>=frame_limit||frame_seq!==completed_frames)
$fatal(1,"PROCESSOR: secuencia %0d; esperada %0d",frame_seq,completed_frames);
if(physical_count<(completed_frames+1)*256)
$fatal(1,"PROCESSOR: frame_begin antes de capturar 256 muestras");
active_frame=completed_frames;
frame_start_cycle=cycle_no;
wave_count=0;spectrum_count=0;
end
if(active_frame>=0&&frame_seq!==active_frame)
$fatal(1,"PROCESSOR: frame_seq cambio durante procesamiento");
if(wave_valid)begin
if(active_frame<0||wave_count>=256||wave_index!==wave_count)
$fatal(1,"PROCESSOR: indice/orden de traza incorrecto idx=%0d esperado=%0d",wave_index,wave_count);
if(wave_sample!==actual_input[active_frame][wave_count])
$fatal(1,"PROCESSOR: traza frame%0d idx%0d got=%0d esperado=%0d",
active_frame,wave_count,wave_sample,actual_input[active_frame][wave_count]);
wave_count=wave_count+1;
phase_waves=phase_waves+1;
end
if(spectrum_valid)begin
if(active_frame<0||wave_count!=256||spectrum_count>128||
spectrum_index!==spectrum_count)
$fatal(1,"PROCESSOR: indice/orden espectral incorrecto idx=%0d esperado=%0d",spectrum_index,spectrum_count);
if(^spectrum_mag===1'bx)
$fatal(1,"PROCESSOR: magnitud desconocida");
got_magnitude=spectrum_mag;
magnitude_error=abs_real(got_magnitude-ideal_magnitude[active_frame][spectrum_count]);
if(magnitude_error>maximum_magnitude_error)
maximum_magnitude_error=magnitude_error;
if(magnitude_error>MAG_TOLERANCE_LSB)
$fatal(1,"PROCESSOR: frame%0d bin%0d mag=%0d DFTideal=%0.6f error=%0.6f",
active_frame,spectrum_count,got_magnitude,
ideal_magnitude[active_frame][spectrum_count],magnitude_error);
if(spectrum_index==128&&!frame_done)
$fatal(1,"PROCESSOR: bin128 debe coincidir con frame_done");
spectrum_count=spectrum_count+1;
phase_bins=phase_bins+1;
end
if(frame_done)begin
if(active_frame<0||!spectrum_valid||spectrum_index!=128||
spectrum_count!=129||wave_count!=256)
$fatal(1,"PROCESSOR: frame_done sin salida completa");
latency=cycle_no-frame_start_cycle;
if(latency>FRAME_DEADLINE)
$fatal(1,"PROCESSOR: latencia %0d excede %0d ciclos",latency,FRAME_DEADLINE);
if(latency>maximum_frame_cycles)maximum_frame_cycles=latency;
$display("PROCESSOR: frame%0d, 256 muestras, 129 bins, %0d ciclos",active_frame,latency);
completed_frames=completed_frames+1;
active_frame=-1;
end
if(active_frame>=0&&cycle_no-frame_start_cycle>FRAME_DEADLINE)
$fatal(1,"PROCESSOR: bloque excedio plazo sin frame_done");
end
end
end
task automatic step_clock;
begin@(posedge clk);#2;end
endtask
task automatic reset_dut;
begin
mode=MODE_OFF;check_cadence=0;
@(negedge clk);rst_n=0;sample_valid=0;sample_signed=0;
repeat(3)@(negedge clk);
rst_n=1;
step_clock();
if(busy||fault_latched||frame_begin||wave_valid||spectrum_valid||frame_done)
$fatal(1,"PROCESSOR: reset no dejo salidas en reposo");
end
endtask
task automatic send_stream(input integer frames,first_family);
integer f,n;
begin
check_cadence=1;
for(f=0;f<frames;f=f+1)begin
for(n=0;n<256;n=n+1)begin
@(negedge clk);
sample_signed=source_word(first_family+f,n);sample_valid=1;
@(negedge clk);sample_valid=0;
repeat(133)@(negedge clk);
end
end
check_cadence=0;
end
endtask
task automatic wait_complete(input integer target);
integer elapsed;
begin
elapsed=0;
while(completed_frames<target&&elapsed<24000)begin
@(negedge clk);elapsed=elapsed+1;
end
if(completed_frames!=target||phase_waves!=256*target||phase_bins!=129*target||
physical_count!=256*target||active_frame!=-1)
$fatal(1,"PROCESSOR: cuenta incompleta frames%0d wave%0d bins%0d muestras%0d",
completed_frames,phase_waves,phase_bins,physical_count);
repeat(3)step_clock();
if(busy||fault_latched)$fatal(1,"PROCESSOR: no volvio a reposo tras terminar");
successful_frames_total=successful_frames_total+target;
end
endtask
task automatic wait_any_wave;
integer elapsed;
begin
elapsed=0;
while(!wave_valid&&elapsed<2000)begin@(negedge clk);elapsed=elapsed+1;end
if(!wave_valid)$fatal(1,"PROCESSOR: no aparecio traza para reset durante copia");
end
endtask
task automatic wait_last_wave;
integer elapsed;
begin
elapsed=0;
while(!(wave_valid&&wave_index==255)&&elapsed<2000)begin
@(negedge clk);elapsed=elapsed+1;
end
if(!(wave_valid&&wave_index==255))
$fatal(1,"PROCESSOR: no aparecio ultima muestra para reset durante FFT");
end
endtask
task automatic check_no_old_frame;
integer elapsed;
begin
for(elapsed=0;elapsed<FRAME_DEADLINE;elapsed=elapsed+1)begin
step_clock();
if(frame_begin||wave_valid||spectrum_valid||frame_done||busy||fault_latched)
$fatal(1,"PROCESSOR: reaparecio operacion anterior al reset");
end
end
endtask
integer n;
initial begin
$dumpfile("signal_processor.vcd");
$dumpvars(1,tb_signal_processor);
reset_dut();frame_limit=3;mode=MODE_SUCCESS;
send_stream(3,0);
wait_complete(3);
$display("PASS: PROCESSOR tres bloques continuos, 768 muestras/387 bins, CONV nominal cada135 ciclos");
reset_dut();mode=MODE_ABORT;
send_stream(1,1);wait_any_wave();
if(wave_index==255)$fatal(1,"PROCESSOR: reset de copia llego demasiado tarde");
reset_dut();check_no_old_frame();
$display("PASS: PROCESSOR reset durante copia, sin publicacion antigua");
mode=MODE_ABORT;
send_stream(1,2);wait_last_wave();
repeat(20)step_clock();
reset_dut();check_no_old_frame();
$display("PASS: PROCESSOR reset durante FFT, sin publicacion antigua");
frame_limit=1;mode=MODE_SUCCESS;
send_stream(1,2);wait_complete(1);
$display("PASS: PROCESSOR bloque fresco despues de reset de calculo");
reset_dut();mode=MODE_OVERLOAD;
@(negedge clk);sample_valid=1;
for(n=0;n<900;n=n+1)begin
sample_signed=(n*97)^16'h5a5a;
@(negedge clk);
end
sample_valid=0;
repeat(20)step_clock();
if(!fault_latched||fault_code!==4'd1)
$fatal(1,"PROCESSOR: sobrecarga no produjo fault1, got%0d",fault_code);
repeat(300)begin
step_clock();
if(!fault_latched||fault_code!==4'd1||frame_begin||wave_valid||
spectrum_valid||frame_done||busy)
$fatal(1,"PROCESSOR: fault de sobrecarga no quedo retenido/abortado");
end
$display("PASS: PROCESSOR sobrecarga detectada, parada retenida sin publicar bloque parcial");
reset_dut();frame_limit=1;mode=MODE_SUCCESS;
send_stream(1,0);wait_complete(1);
$display("PASS: PROCESSOR recuperacion de sobrecarga por reset");
$display("PASS: SIGNAL_PROCESSOR integracion, %0d bloques completos; latencia maxima%0d ciclos, error magnitud%0.6f LSB",
successful_frames_total,maximum_frame_cycles,maximum_magnitude_error);
$finish;
end
initial begin#20000000;$fatal(1,"PROCESSOR: timeout global20ms");end
endmodule
