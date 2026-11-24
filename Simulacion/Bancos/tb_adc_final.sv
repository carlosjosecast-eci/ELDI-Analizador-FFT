`timescale 1ns/1ps
module tb_adc_final#(
parameter bit STANDALONE=1'b1
)(
output reg done=1'b0
);
localparam integer STARTUP_CYCLES=5;
localparam integer SAMPLE_PERIOD_CYCLES=135;
localparam realtime HALF_CLOCK_NS=18.5185;
localparam realtime DATA_ACCESS_NS=37.0;
reg clk=1'b0;
reg rst_n=1'b0;
reg adc_busy=1'b0;
reg adc_fd=1'bz;
reg[7:0]adc_db=8'hzz;
wire adc_convst,adc_cs_n,adc_rd_n,adc_reset;
wire signed[15:0]sample_signed;
wire sample_valid,fault_latched;
wire[3:0]fault_code;
ad7606_byte_reader#(.STARTUP_CYCLES(STARTUP_CYCLES))dut(
.clk(clk),.rst_n(rst_n),.adc_busy(adc_busy),.adc_fd(adc_fd),.adc_db(adc_db),
.adc_convst(adc_convst),.adc_cs_n(adc_cs_n),.adc_rd_n(adc_rd_n),
.adc_reset(adc_reset),.sample_signed(sample_signed),.sample_valid(sample_valid),
.fault_latched(fault_latched),.fault_code(fault_code)
);
always#(HALF_CLOCK_NS)clk=~clk;
integer clocks=0;
integer conversions=0;
integer reads=0;
integer published=0;
integer last_reset_fall;
reg result_ready=1'b0;
always@(posedge clk)clocks=clocks+1;
always@(posedge adc_convst)if(rst_n)conversions=conversions+1;
always@(negedge adc_cs_n)begin
if(rst_n&&!result_ready)$fatal(1,"ADC FINAL: CS antes de terminar BUSY");
end
always@(negedge adc_rd_n)begin
if(rst_n)begin
if(adc_cs_n||adc_busy||!result_ready)
$fatal(1,"ADC FINAL: RD fuera de una lectura válida de AIN1");
reads=reads+1;
end
end
always@(posedge sample_valid)begin
if(rst_n)begin
if(!result_ready)$fatal(1,"ADC FINAL: publicación sin resultado de conversión");
published=published+1;
end
end
task automatic reset_reader;
integer reset_released;
integer reset_started;
begin
@(negedge clk);
rst_n=1'b0;
adc_busy=1'b0;
adc_fd=1'bz;
adc_db=8'hzz;
result_ready=1'b0;
#1;
if({adc_convst,adc_cs_n,adc_rd_n,adc_reset,sample_valid,
fault_latched,fault_code}!==10'b0110000000)
$fatal(1,"ADC FINAL: reset no limpia salidas y error retenido");
repeat(2)@(negedge clk);
rst_n=1'b1;
reset_released=clocks;
@(posedge adc_reset);
#1;
reset_started=clocks;
if(reset_started-reset_released!=STARTUP_CYCLES)
$fatal(1,"ADC FINAL: espera de arranque incorrecta");
@(negedge adc_reset);
#1;
last_reset_fall=clocks;
if(last_reset_fall-reset_started!=4)
$fatal(1,"ADC FINAL: RESET debe durar cuatro ciclos");
end
endtask
task automatic start_conversion(input integer expected_clock,output integer started_at);
begin
@(posedge adc_convst);
#1;
started_at=clocks;
if(started_at!=expected_clock||!adc_cs_n||!adc_rd_n||adc_reset||sample_valid)
$fatal(1,"ADC FINAL: CONVST fuera de tiempo o bus activo (ciclo %0d, esperado %0d)",
started_at,expected_clock);
end
endtask
task automatic finish_conversion(input realtime conversion_ns);
integer start_clock;
begin
start_clock=clocks;
#16;
adc_busy=1'b1;
@(negedge adc_convst);
#1;
if(clocks-start_clock!=2)
$fatal(1,"ADC FINAL: CONVST debe durar dos ciclos");
#(conversion_ns-(4.0*HALF_CLOCK_NS+1.0));
adc_busy=1'b0;
result_ready=1'b1;
end
endtask
task automatic send_byte(
input[7:0]value,
input fd_value,
input integer low_cycles,
output integer rd_start,
output integer rd_end
);
begin
@(negedge adc_rd_n);
#1;
rd_start=clocks;
#(DATA_ACCESS_NS-1.0);
adc_db=value;
adc_fd=fd_value;
@(posedge adc_rd_n);
#1;
rd_end=clocks;
if(rd_end-rd_start!=low_cycles)
$fatal(1,"ADC FINAL: RD bajo %0d ciclos, se esperaban %0d",
rd_end-rd_start,low_cycles);
adc_db=8'hzz;
adc_fd=1'bz;
end
endtask
task automatic publish_word(input[15:0]expected_word,input realtime conversion_ns);
integer cs_start;
integer msb_start,msb_end,lsb_start,lsb_end;
integer initial_reads,initial_samples;
begin
initial_reads=reads;
initial_samples=published;
finish_conversion(conversion_ns);
@(negedge adc_cs_n);
#1;
cs_start=clocks;
send_byte(expected_word[15:8],1'b1,10,msb_start,msb_end);
send_byte(expected_word[7:0],1'b1,2,lsb_start,lsb_end);
@(posedge sample_valid);
#1;
if(msb_start-cs_start!=1||lsb_start-msb_end!=1||clocks-lsb_end!=1)
$fatal(1,"ADC FINAL: tiempos de CS, separación RD o publicación incorrectos");
if(reads-initial_reads!=2||published-initial_samples!=1||
sample_signed!==$signed(expected_word)||fault_latched||!adc_cs_n||!adc_rd_n)
$fatal(1,"ADC FINAL: muestra %h, esperada %h",sample_signed,expected_word);
result_ready=1'b0;
@(posedge clk);
#1;
if(sample_valid)$fatal(1,"ADC FINAL: sample_valid debe durar un ciclo");
end
endtask
task automatic expect_fault(input[3:0]expected_code,input integer expected_published);
integer conversion_at_fault,reads_at_fault;
begin
wait(fault_latched===1'b1);
#1;
if(fault_code!==expected_code||!adc_cs_n||!adc_rd_n||adc_convst||sample_valid)
$fatal(1,"ADC FINAL: diagnóstico %0d, esperado %0d",fault_code,expected_code);
conversion_at_fault=conversions;
reads_at_fault=reads;
repeat(SAMPLE_PERIOD_CYCLES+1)@(posedge clk);
#1;
if(!fault_latched||fault_code!==expected_code||conversions!=conversion_at_fault||
reads!=reads_at_fault||published!=expected_published)
$fatal(1,"ADC FINAL: el fallo %0d no detuvo adquisición hasta reset",expected_code);
end
endtask
integer started;
integer next_start;
integer ignored_rd_start,ignored_rd_end;
integer samples_before;
initial begin
reset_reader();
start_conversion(last_reset_fall+2,started);
next_start=started+SAMPLE_PERIOD_CYCLES;
publish_word(16'h0000,3450.0);
start_conversion(next_start,started);
next_start=started+SAMPLE_PERIOD_CYCLES;
publish_word(16'h7fff,4200.0);
start_conversion(next_start,started);
next_start=started+SAMPLE_PERIOD_CYCLES;
publish_word(16'h8000,3850.0);
start_conversion(next_start,started);
next_start=started+SAMPLE_PERIOD_CYCLES;
publish_word(16'hffff,4200.0);
start_conversion(next_start,started);
publish_word(16'h93c7,3450.0);
samples_before=published;
reset_reader();
start_conversion(last_reset_fall+2,started);
expect_fault(4'd1,samples_before);
reset_reader();
start_conversion(last_reset_fall+2,started);
#16;
adc_busy=1'b1;
expect_fault(4'd2,samples_before);
reset_reader();
start_conversion(last_reset_fall+2,started);
finish_conversion(3450.0);
send_byte(8'h42,1'b0,10,ignored_rd_start,ignored_rd_end);
expect_fault(4'd3,samples_before);
reset_reader();
start_conversion(last_reset_fall+2,started);
finish_conversion(3850.0);
send_byte(8'h96,1'b1,10,ignored_rd_start,ignored_rd_end);
send_byte(8'h10,1'bz,2,ignored_rd_start,ignored_rd_end);
expect_fault(4'd3,samples_before);
reset_reader();
start_conversion(last_reset_fall+2,started);
finish_conversion(3450.0);
@(negedge adc_rd_n);
#1;
adc_busy=1'b1;
expect_fault(4'd4,samples_before);
reset_reader();
start_conversion(last_reset_fall+2,started);
publish_word(16'h28a5,3450.0);
adc_busy=1'b1;
samples_before=published;
expect_fault(4'd5,samples_before);
reset_reader();
start_conversion(last_reset_fall+2,started);
finish_conversion(3450.0);
@(negedge adc_rd_n);
reset_reader();
if(published!=samples_before)
$fatal(1,"ADC FINAL: reset en lectura publicó datos parciales");
start_conversion(last_reset_fall+2,started);
publish_word(16'hf0a6,4200.0);
$display("PASS: ADC FINAL FD73, %0d muestras, MSB/LSB, 135 ciclos, fallos 1..5 y recuperación",published);
done=1'b1;
if(STANDALONE)$finish;
end
initial begin
#250000;
if(!done)$fatal(1,"ADC FINAL: tiempo máximo del banco excedido");
end
endmodule
