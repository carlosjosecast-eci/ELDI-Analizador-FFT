`timescale 1ns/1ps
module tb_sample_capture;
reg clk=1'b0;
always#5clk=~clk;
reg rst_n;
reg sample_valid;
reg signed[15:0]sample_signed;
wire block_valid;
wire block_bank;
wire[31:0]block_seq;
reg block_release;
wire overrun_latched;
reg rd_en;
reg rd_bank;
reg[7:0]rd_addr;
wire signed[15:0]rd_sample;
wire rd_valid;
reg expected_valid;
reg expected_bank;
reg[31:0]expected_seq;
reg expected_overrun;
reg expected_next_bank;
reg[31:0]expected_next_seq;
integer expected_pattern_id;
integer checks;
integer read_checks;
integer i;
integer j;
sample_capture dut(
.clk(clk),.rst_n(rst_n),
.sample_valid(sample_valid),.sample_signed(sample_signed),
.block_valid(block_valid),.block_bank(block_bank),.block_seq(block_seq),
.block_release(block_release),.overrun_latched(overrun_latched),
.rd_en(rd_en),.rd_bank(rd_bank),.rd_addr(rd_addr),
.rd_sample(rd_sample),.rd_valid(rd_valid)
);
function automatic signed[15:0]pattern(
input integer block_id,
input integer address
);
begin
case(address)
0:pattern=16'h8000+block_id;
1:pattern=16'h7fff-block_id;
2:pattern=16'hffff;
3:pattern=16'h0000;
254:pattern=16'h1234^block_id;
255:pattern=16'hfedc^block_id;
default:pattern=(address*73+block_id*997)^16'ha55a;
endcase
end
endfunction
task automatic check_outputs(
input reg expected_rd_valid,
input reg signed[15:0]expected_rd_sample
);
begin
checks=checks+1;
if(block_valid!==expected_valid||
block_bank!==expected_bank||block_seq!==expected_seq||
overrun_latched!==expected_overrun)
$fatal(1,
"Metadata t=%0t: valid=%b/%b banco=%b/%b seq=%0d/%0d overrun=%b/%b",
$time,block_valid,expected_valid,block_bank,expected_bank,
block_seq,expected_seq,overrun_latched,expected_overrun);
if(rd_valid!==expected_rd_valid)
$fatal(1,"rd_valid t=%0t: obtenido=%b esperado=%b",
$time,rd_valid,expected_rd_valid);
if(expected_rd_valid)begin
read_checks=read_checks+1;
if(rd_sample!==expected_rd_sample)
$fatal(1,
"Lectura t=%0t banco=%0d addr=%0d dato=%h esperado=%h",
$time,rd_bank,rd_addr,rd_sample,expected_rd_sample);
end
end
endtask
task automatic cycle(
input reg next_sample_valid,
input reg signed[15:0]next_sample,
input reg next_release,
input reg next_rd_en,
input reg next_rd_bank,
input reg[7:0]next_rd_addr,
input integer publication_id,
input reg expect_fault
);
reg expected_read;
reg signed[15:0]expected_word;
begin
@(negedge clk);
sample_valid=next_sample_valid;
sample_signed=next_sample;
block_release=next_release;
rd_en=next_rd_en;
rd_bank=next_rd_bank;
rd_addr=next_rd_addr;
expected_read=next_rd_en&&expected_valid&&
(next_rd_bank==expected_bank);
expected_word=pattern(expected_pattern_id,next_rd_addr);
if(!expected_overrun)begin
if(expect_fault)begin
expected_overrun=1'b1;
end else begin
if(next_release)
expected_valid=1'b0;
if(publication_id>=0)begin
expected_valid=1'b1;
expected_bank=expected_next_bank;
expected_seq=expected_next_seq;
expected_pattern_id=publication_id;
expected_next_bank=~expected_next_bank;
expected_next_seq=expected_next_seq+32'd1;
end
end
end
@(posedge clk);
#1;
check_outputs(expected_read,expected_word);
end
endtask
task automatic reset_capture;
begin
@(negedge clk);
rst_n=1'b0;
sample_valid=1'b0;
sample_signed=16'sd0;
block_release=1'b0;
rd_en=1'b0;
rd_bank=1'b0;
rd_addr=8'd0;
expected_valid=1'b0;
expected_bank=1'b0;
expected_seq=32'd0;
expected_overrun=1'b0;
expected_next_bank=1'b0;
expected_next_seq=32'd0;
expected_pattern_id=-1;
#1;
check_outputs(1'b0,16'sd0);
repeat(2)@(posedge clk);
#1rst_n=1'b1;
end
endtask
task automatic send_block(
input integer block_id,
input reg add_gaps,
input reg publish_at_end,
input reg fault_at_end
);
integer address;
begin
for(address=0;address<256;address=address+1)begin
if(add_gaps&&((address%13)==0))
cycle(1'b0,16'hdead,1'b0,1'b1,
expected_next_bank,address,-1,1'b0);
cycle(1'b1,pattern(block_id,address),1'b0,1'b0,1'b0,
8'd0,((address==255)&&publish_at_end)?block_id:-1,
(address==255)&&fault_at_end);
end
end
endtask
task automatic read_published_block;
integer address;
begin
for(address=0;address<256;address=address+1)
cycle(1'b0,16'sd0,1'b0,1'b1,expected_bank,
address,-1,1'b0);
end
endtask
initial begin
rst_n=1'b0;
sample_valid=1'b0;
sample_signed=16'sd0;
block_release=1'b0;
rd_en=1'b0;
rd_bank=1'b0;
rd_addr=8'd0;
expected_valid=1'b0;
expected_bank=1'b0;
expected_seq=32'd0;
expected_overrun=1'b0;
expected_next_bank=1'b0;
expected_next_seq=32'd0;
expected_pattern_id=-1;
checks=0;
read_checks=0;
reset_capture();
cycle(1'b0,16'sd0,1'b1,1'b1,1'b0,8'd255,-1,1'b0);
cycle(1'b0,16'sd0,1'b0,1'b1,1'b1,8'd0,-1,1'b0);
send_block(0,1'b1,1'b1,1'b0);
cycle(1'b0,16'sd0,1'b0,1'b1,1'b0,8'd255,-1,1'b0);
cycle(1'b0,16'sd0,1'b0,1'b1,1'b1,8'd0,-1,1'b0);
for(j=1;j<4;j=j+1)begin
for(i=0;i<256;i=i+1)
cycle(1'b1,pattern(j,i),(i==255),1'b1,expected_bank,
(j==2)?(255-i):i,(i==255)?j:-1,1'b0);
end
read_published_block();
cycle(1'b0,16'sd0,1'b1,1'b0,1'b0,8'd0,-1,1'b0);
cycle(1'b0,16'sd0,1'b1,1'b1,expected_bank,8'd255,-1,1'b0);
send_block(4,1'b0,1'b1,1'b0);
read_published_block();
cycle(1'b0,16'sd0,1'b1,1'b1,expected_bank,8'd255,-1,1'b0);
reset_capture();
for(i=0;i<131;i=i+1)
cycle(1'b1,pattern(20,i),1'b0,1'b0,1'b0,8'd0,-1,1'b0);
reset_capture();
cycle(1'b0,16'sd0,1'b0,1'b1,1'b0,8'd130,-1,1'b0);
send_block(21,1'b1,1'b1,1'b0);
read_published_block();
reset_capture();
send_block(10,1'b0,1'b1,1'b0);
send_block(11,1'b0,1'b0,1'b1);
for(i=0;i<600;i=i+1)
cycle(1'b1,pattern(12,i%256),(i==200),1'b1,
1'b0,i%256,-1,1'b0);
cycle(1'b0,16'sd0,1'b1,1'b1,1'b1,8'd0,-1,1'b0);
read_published_block();
reset_capture();
send_block(22,1'b0,1'b1,1'b0);
read_published_block();
cycle(1'b0,16'sd0,1'b1,1'b0,1'b0,8'd0,-1,1'b0);
$display("PASS: sample_capture, comprobaciones=%0d lecturas=%0d",
checks,read_checks);
$finish;
end
initial begin
$dumpfile("sample_capture.vcd");
$dumpvars(0,tb_sample_capture);
#200000;
$fatal(1,"TIMEOUT: sample_capture no termino");
end
endmodule
