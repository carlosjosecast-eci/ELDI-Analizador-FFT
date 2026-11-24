`timescale 1ns/1ps
module tb_presentation_overlay#(
parameter bit STANDALONE=1'b1
)(
output reg done=1'b0
);
localparam integer RAW_STAGES=2;
localparam integer OVERLAY_STAGES=2;
localparam integer TOTAL_STAGES=RAW_STAGES+OVERLAY_STAGES;
localparam[23:0]TEXT=24'hacb8c8;
localparam[23:0]TITLE=24'he8eef6;
localparam[23:0]TICK=24'h758498;
localparam[23:0]RED=24'hff0000;
localparam[23:0]GRAY=24'h202020;
reg pixel_clk=1'b0;
reg wr_clk27=1'b0;
reg rst_n=1'b0;
reg[10:0]x=11'd0;
reg[9:0]y=10'd0;
reg mode=1'b0;
reg frame_start=1'b0;
reg adc_fault=1'b0;
reg processor_fault=1'b0;
reg display_fault=1'b0;
reg[3:0]adc_code=4'd0;
reg[3:0]processor_code=4'd0;
reg[23:0]source_rgb=24'd0;
reg[2:0]source_controls=3'd0;
reg[23:0]raw_rgb_q,raw_rgb;
reg[2:0]raw_controls_q,raw_controls;
wire[10:0]diag_x;
wire[9:0]diag_y;
wire[23:0]diagnostic_rgb;
wire[23:0]rgb_out;
wire de_out,hsync_out,vsync_out;
always@(posedge pixel_clk or negedge rst_n)begin
if(!rst_n)begin
raw_rgb_q<=24'd0;
raw_rgb<=24'd0;
raw_controls_q<=3'd0;
raw_controls<=3'd0;
end else begin
raw_rgb_q<=source_rgb;
raw_rgb<=raw_rgb_q;
raw_controls_q<=source_controls;
raw_controls<=raw_controls_q;
end
end
presentation_diagnostic_layout layout(
.x(x),.y(y),.diag_x(diag_x),.diag_y(diag_y)
);
diagnostic_overlay diagnostic(
.wr_clk27(wr_clk27),.wr_rst_n(rst_n),.pix_clk(pixel_clk),.pix_rst_n(rst_n),
.pixel_frame_start(frame_start),.pixel_x(diag_x),.pixel_y(diag_y),
.video_de(raw_controls[2]),.in_rgb(raw_rgb),.adc_fault(adc_fault),
.adc_code(adc_code),.processor_fault(processor_fault),
.processor_code(processor_code),.display_fault(display_fault),.out_rgb(diagnostic_rgb)
);
presentation_overlay dut(
.pixel_clk(pixel_clk),.rst_n(rst_n),.x(x),.y(y),.mode(mode),
.rgb_in(diagnostic_rgb),.de_in(raw_controls[2]),
.hsync_in(raw_controls[1]),.vsync_in(raw_controls[0]),
.rgb_out(rgb_out),.de_out(de_out),.hsync_out(hsync_out),.vsync_out(vsync_out)
);
always#6.734pixel_clk=~pixel_clk;
always#18.518wr_clk27=~wr_clk27;
reg[47:0]expected[0:TOTAL_STAGES-1];
reg[47:0]expected_pixel;
integer checks=0;
integer stage;
task automatic reset_pipeline;
begin
@(negedge pixel_clk);
rst_n=1'b0;
frame_start=1'b0;
adc_fault=1'b0;
processor_fault=1'b0;
display_fault=1'b0;
adc_code=4'd0;
processor_code=4'd0;
source_rgb=24'd0;
source_controls=3'd0;
for(stage=0;stage<TOTAL_STAGES;stage=stage+1)
expected[stage]=48'd0;
repeat(2)@(posedge wr_clk27);
#1;
if({rgb_out,de_out,hsync_out,vsync_out}!==27'd0)
$fatal(1,"Reset no limpia RGB/DE/HS/VS");
@(negedge pixel_clk);
rst_n=1'b1;
end
endtask
task automatic send_pixel(
input[10:0]col,
input[9:0]row,
input fft_mode,
input[23:0]in_color,
input[2:0]controls,
input[23:0]compare_color
);
begin
@(negedge pixel_clk);
x=col;
y=row;
mode=fft_mode;
source_rgb=in_color;
source_controls=controls;
for(stage=TOTAL_STAGES-1;stage>0;stage=stage-1)
expected[stage]=expected[stage-1];
expected[0]={col,row,controls,compare_color};
expected_pixel=expected[TOTAL_STAGES-1];
@(posedge pixel_clk);
#1;
if({de_out,hsync_out,vsync_out}!==expected_pixel[26:24])
$fatal(1,"Controles corridos en (%0d,%0d): %b vs %b",
expected_pixel[47:37],expected_pixel[36:27],
{de_out,hsync_out,vsync_out},expected_pixel[26:24]);
if(rgb_out!==expected_pixel[23:0])
$fatal(1,"RGB distinto en (%0d,%0d): %06h vs %06h",
expected_pixel[47:37],expected_pixel[36:27],
rgb_out,expected_pixel[23:0]);
checks=checks+1;
end
endtask
task automatic expect_passthrough(
input[10:0]col,
input[9:0]row,
input fft_mode,
input[23:0]color,
input[2:0]controls
);
begin
send_pixel(col,row,fft_mode,color,controls,
controls[2]?color:24'd0);
end
endtask
task automatic scan_boxes(input integer count);
integer box;
reg[10:0]left;
reg[23:0]box_rgb;
begin
for(box=0;box<8;box=box+1)begin
left=11'd128+11'd16*box;
box_rgb=(box<count)?RED:GRAY;
send_pixel(left,10'd103,1'b0,24'h1b325f,3'b111,box_rgb);
send_pixel(left+11'd11,10'd114,1'b1,24'h869ab3,3'b101,box_rgb);
expect_passthrough(left-11'd1,10'd103,1'b0,24'h009596,3'b110);
expect_passthrough(left+11'd12,10'd114,1'b1,24'h01828b,3'b100);
expect_passthrough(left,10'd102,1'b0,24'h353896,3'b101);
expect_passthrough(left,10'd115,1'b1,24'h9a27cb,3'b110);
expect_passthrough(left,10'd103,1'b0,24'h27cab5,3'b011);
end
end
endtask
task automatic flush_pipeline;
integer i;
begin
for(i=0;i<TOTAL_STAGES;i=i+1)
expect_passthrough(11'd1649,10'd749,1'b0,24'hb19ca2,{1'b0,i[1:0]});
end
endtask
integer sample;
integer i;
integer code;
reg[10:0]probe_x;
reg[9:0]probe_y;
reg[23:0]probe_rgb;
initial begin
reset_pipeline();
for(sample=0;sample<2;sample=sample+1)begin
expect_passthrough(11'd127,10'd127,sample[0],24'h19375a,3'b100);
expect_passthrough(11'd1160,10'd640,sample[0],24'hb78126,3'b111);
for(i=0;i<256;i=i+1)begin
probe_x=11'd128+((i*11'd241)&11'd1023);
probe_y=10'd128+((i*10'd171)&10'd511);
probe_rgb={i[7:0],i[7:0]^8'hfc,i[7:0]+8'h2d};
expect_passthrough(probe_x,probe_y,sample[0],probe_rgb,{1'b1,i[1:0]});
end
end
send_pixel(11'd128,10'd20,1'b0,24'h112233,3'b100,TEXT);
send_pixel(11'd132,10'd40,1'b1,24'h112233,3'b111,TITLE);
send_pixel(11'd130,10'd82,1'b0,24'h112233,3'b110,TEXT);
expect_passthrough(11'd768,10'd105,1'b1,24'h112233,3'b101);
send_pixel(11'd1024,10'd9,1'b1,24'h112233,3'b110,24'h454a52);
send_pixel(11'd1023,10'd8,1'b1,24'h112233,3'b110,24'h9aa3af);
send_pixel(11'd1036,10'd13,1'b1,24'h112233,3'b110,24'hffffff);
expect_passthrough(11'd1022,10'd8,1'b0,24'h112233,3'b101);
expect_passthrough(11'd1036,10'd13,1'b0,24'h112233,3'b011);
send_pixel(11'd552,10'd690,1'b0,24'h324567,3'b100,TEXT);
send_pixel(11'd516,10'd690,1'b1,24'h456748,3'b110,TEXT);
expect_passthrough(11'd516,10'd690,1'b0,24'h789321,3'b100);
send_pixel(11'd1135,10'd656,1'b1,24'h27486a,3'b111,TEXT);
send_pixel(11'd1115,10'd656,1'b0,24'ha47651,3'b101,TEXT);
send_pixel(11'd128,10'd645,1'b1,24'h192921,3'b110,TICK);
send_pixel(11'd384,10'd645,1'b0,24'h352911,3'b100,TICK);
send_pixel(11'd640,10'd645,1'b1,24'h124921,3'b101,TICK);
send_pixel(11'd896,10'd645,1'b0,24'h338472,3'b110,TICK);
send_pixel(11'd1148,10'd645,1'b0,24'h803562,3'b100,TICK);
send_pixel(11'd1152,10'd645,1'b1,24'h265416,3'b111,TICK);
expect_passthrough(11'd1148,10'd645,1'b1,24'h245962,3'b110);
expect_passthrough(11'd1152,10'd645,1'b0,24'h129866,3'b101);
scan_boxes(0);
flush_pipeline();
for(code=1;code<=8;code=code+1)begin
reset_pipeline();
@(negedge wr_clk27);
adc_fault=(code<=5);
adc_code=code[3:0];
processor_fault=(code==6||code==7);
processor_code=(code==6)?4'd1:4'd2;
display_fault=(code==8);
repeat(4)@(posedge wr_clk27);
@(negedge pixel_clk);
frame_start=1'b1;
@(negedge pixel_clk);
frame_start=1'b0;
scan_boxes(code);
flush_pipeline();
end
reset_pipeline();
scan_boxes(0);
flush_pipeline();
$display("PASS: PRESENTATION_OVERLAY, %0d ciclos, grafica, texto, logo, diagnosticos 0..8 y controles",checks);
done=1'b1;
if(STANDALONE)$finish;
end
initial begin
#50000;
if(!done)$fatal(1,"PRESENTACION: tiempo maximo excedido");
end
endmodule
