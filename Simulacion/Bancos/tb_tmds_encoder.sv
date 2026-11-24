`timescale 1ns/1ps
module tb_tmds_encoder;
localparam real PIXEL_NS=1000.0/74.25;
reg clk=0;
always#(PIXEL_NS/2.0)clk=!clk;
reg rst_n=0,de=0,c0=0,c1=0;
reg[7:0]data=0;
wire[9:0]symbol;
integer running_balance=0;
integer data_checks=0,control_checks=0,reset_checks=0,unique_codes=0;
integer states[0:31],parent[0:31],parent_byte[0:31],number_states=1;
reg covered[0:31][0:255];
reg active_codes[0:1023];
real last_pixel_edge=0.0;
reg monitor_changes=0;
reg[31:0]random_state=32'h71d52026;
tmds_encoder dut(.clk(clk),.rst_n(rst_n),.de(de),.data(data),
.c0(c0),.c1(c1),.symbol(symbol));
function automatic integer abs_integer(input integer x);
abs_integer=(x<0)?-x:x;
endfunction
function automatic integer symbol_balance(input reg[9:0]code);
integer i,total;
begin
total=0;
for(i=0;i<10;i=i+1)if(code[i])total=total+1;
symbol_balance=2*total-10;
end
endfunction
function automatic integer transitions(input reg[7:0]value);
integer i,total;
begin
total=0;
for(i=1;i<8;i=i+1)if(value[i]!=value[i-1])total=total+1;
transitions=total;
end
endfunction
function automatic reg[9:0]control_code(input reg[1:0]control);
begin
case(control)
0:control_code=10'b1101010100;
1:control_code=10'b0010101011;
2:control_code=10'b0101010100;
3:control_code=10'b1010101011;
endcase
end
endfunction
function automatic reg[7:0]decode_pixel(input reg[9:0]code);
reg[7:0]recovered_payload,delta;
begin
recovered_payload=code[7:0]^{8{code[9]}};
delta=recovered_payload^(recovered_payload<<1);
if(!code[8])delta=delta^8'hfe;
decode_pixel=delta;
end
endfunction
function automatic reg[9:0]reference_symbol(input reg[7:0]pixel,input integer rd);
reg[7:0]prefix_xor,prefix_xnor,payload;
reg q8;
reg[9:0]plain,inverted;
integer i,j,parity,plain_rd,inverted_rd,ones;
begin
prefix_xor=0;
for(i=0;i<8;i=i+1)begin
parity=0;
for(j=0;j<=i;j=j+1)parity=parity^pixel[j];
prefix_xor[i]=parity;
end
prefix_xnor=prefix_xor^8'haa;
q8=(transitions(prefix_xor)<transitions(prefix_xnor));
payload=q8?prefix_xor:prefix_xnor;
plain={1'b0,q8,payload};
inverted={1'b1,q8,~payload};
ones=0;
for(i=0;i<8;i=i+1)if(payload[i])ones=ones+1;
if(rd==0||ones==4)reference_symbol=q8?plain:inverted;
else begin
plain_rd=rd+symbol_balance(plain);
inverted_rd=rd+symbol_balance(inverted);
if(abs_integer(plain_rd)==abs_integer(inverted_rd))
$fatal(1,"REF TMDS: empate inesperado fuera de casos canonicos");
reference_symbol=(abs_integer(plain_rd)<abs_integer(inverted_rd))?plain:inverted;
end
end
endfunction
always@(posedge clk)last_pixel_edge=$realtime;
always@(symbol)
if(rst_n&&monitor_changes&&$realtime!=last_pixel_edge)
$fatal(1,"TMDS: salida cambio fuera de flanco de pixel");
task automatic reset_encoder;
begin
@(negedge clk);rst_n=0;de=0;c0=0;c1=0;data=0;
#1;
if(symbol!==10'b1101010100)$fatal(1,"TMDS: reset no produce control00");
running_balance=0;
repeat(2)@(negedge clk);
rst_n=1;
#1;
if(symbol!==10'b1101010100)$fatal(1,"TMDS: liberar reset cambio salida");
reset_checks=reset_checks+1;
end
endtask
task automatic drive_control(input reg[1:0]control);
reg[9:0]held;
begin
@(negedge clk);held=symbol;
de=0;c1=control[1];c0=control[0];data=~data;
#1;
if(symbol!==held)$fatal(1,"TMDS: control atraviesa registro antes del flanco");
@(posedge clk);#1;
if(symbol!==control_code(control))
$fatal(1,"TMDS: control%0d incorrecto, got=%b",control,symbol);
running_balance=0;
control_checks=control_checks+1;
end
endtask
task automatic drive_pixel(input reg[7:0]pixel);
reg[9:0]expected,held;
reg[7:0]payload;
integer i;
begin
expected=reference_symbol(pixel,running_balance);
@(negedge clk);held=symbol;
de=1;data=pixel;
c0=~c0;c1=c0^c1;
#1;
if(symbol!==held)$fatal(1,"TMDS: dato atraviesa registro antes del flanco");
@(posedge clk);#1;
if(symbol!==expected)
$fatal(1,"TMDS: pixel=%h RD=%0d got=%b expected=%b",pixel,running_balance,symbol,expected);
if(decode_pixel(symbol)!==pixel)
$fatal(1,"TMDS: el simbolo no recupera pixel=%h",pixel);
for(i=0;i<4;i=i+1)
if(symbol===control_code(i))$fatal(1,"TMDS: datos emitieron simbolo reservado de control");
payload=symbol[7:0]^{8{symbol[9]}};
if(transitions(payload)>3)$fatal(1,"TMDS: primera etapa no minimizo transiciones");
running_balance=running_balance+symbol_balance(symbol);
if(running_balance<-8||running_balance>8||running_balance%2!=0)
$fatal(1,"TMDS: desequilibrio emitido fuera del conjunto alcanzable %0d",running_balance);
if(!active_codes[symbol])begin active_codes[symbol]=1;unique_codes=unique_codes+1;end
data_checks=data_checks+1;
end
endtask
task automatic discover_states;
integer cursor,p,next_rd,found,i;
reg[9:0]code;
begin
states[0]=0;parent[0]=-1;parent_byte[0]=0;number_states=1;
cursor=0;
while(cursor<number_states)begin
for(p=0;p<256;p=p+1)begin
code=reference_symbol(p,states[cursor]);
next_rd=states[cursor]+symbol_balance(code);
found=-1;
for(i=0;i<number_states;i=i+1)if(states[i]==next_rd)found=i;
if(found<0)begin
if(number_states>=32)$fatal(1,"TMDS: grafo de disparidad no cerro");
states[number_states]=next_rd;
parent[number_states]=cursor;parent_byte[number_states]=p;
number_states=number_states+1;
end
end
cursor=cursor+1;
end
if(number_states!=9)$fatal(1,"TMDS: numero de estados alcanzables=%0d",number_states);
for(i=0;i<number_states;i=i+1)
if(states[i]<-8||states[i]>8||states[i]%2!=0)
$fatal(1,"TMDS: estado alcanzable inesperado=%0d",states[i]);
end
endtask
task automatic reach_state(input integer state_index);
integer path[0:31];
integer count,cursor,j;
begin
drive_control(0);
count=0;cursor=state_index;
while(cursor!=0)begin
if(count>=32)$fatal(1,"TMDS: camino BFS ciclico");
path[count]=parent_byte[cursor];count=count+1;cursor=parent[cursor];
end
for(j=count-1;j>=0;j=j-1)drive_pixel(path[j]);
if(running_balance!=states[state_index])$fatal(1,"TMDS: no alcanzo RD objetivo");
end
endtask
integer s,p,n,c,transitions_checked;
reg[9:0]held_symbol;
initial begin
$dumpfile("tmds_encoder.vcd");$dumpvars(0,tb_tmds_encoder);
for(s=0;s<32;s=s+1)for(p=0;p<256;p=p+1)covered[s][p]=0;
for(p=0;p<1024;p=p+1)active_codes[p]=0;
reset_encoder();monitor_changes=1;discover_states();
transitions_checked=0;
for(s=0;s<number_states;s=s+1)begin
for(p=0;p<256;p=p+1)begin
reach_state(s);drive_pixel(p);
covered[s][p]=1;transitions_checked=transitions_checked+1;
repeat(8)drive_pixel(0);
end
end
for(s=0;s<number_states;s=s+1)for(p=0;p<256;p=p+1)
if(!covered[s][p])$fatal(1,"TMDS: transicion sin probar");
if(transitions_checked!=2304||unique_codes!=460)
$fatal(1,"TMDS: cobertura grafo/codigos incompleta: %0d/%0d",transitions_checked,unique_codes);
$display("PASS: TMDS 9 estados RD x256 datos=2304 transiciones, 460 simbolos activos");
for(s=0;s<number_states;s=s+1)begin
for(c=0;c<4;c=c+1)begin
reach_state(s);drive_control(c);drive_pixel(1);
end
reach_state(s);reset_encoder();drive_pixel(1);
end
drive_control(0);held_symbol=symbol;
#1;de=1;data=8'hff;c0=1;c1=1;
#1;
if(symbol!==held_symbol)$fatal(1,"TMDS: glitch de entrada paso a salida");
de=0;data=0;c0=0;c1=0;
drive_control(0);
for(n=0;n<1024;n=n+1)drive_pixel((n%2==0)?0:255);
for(n=0;n<4096;n=n+1)begin
random_state=random_state*32'd1664525+32'd1013904223;
if(n%17==0)drive_control(random_state[1:0]);
else drive_pixel(random_state[31:24]);
end
drive_control(3);drive_control(2);drive_control(1);drive_control(0);
reset_encoder();drive_pixel(0);drive_pixel(255);
$display("PASS: TMDS controles/DE/reset, decoder, balance emitido y salida registrada; datos=%0d controles=%0d resets=%0d",
data_checks,control_checks,reset_checks);
$finish;
end
initial begin#1000000;$fatal(1,"TMDS: timeout global");end
endmodule
