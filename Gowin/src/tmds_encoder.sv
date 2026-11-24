`timescale 1ns/1ps

// Un canal DVI/TMDS: componente de color de 8 bits -> simbolo de 10 bits.
// La salida se registra con el reloj de pixel. En el adaptador fisico posterior
// debe enviarse symbol[0] primero. No contiene serializador ni primitivas.
module tmds_encoder (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       de,
    input  logic [7:0] data,
    input  logic       c0,
    input  logic       c1,
    output logic [9:0] symbol
);
    localparam logic [9:0] CONTROL_00 = 10'b1101010100;
    logic signed [5:0] disparity, disparity_next;
    logic [9:0] symbol_next;
    logic [8:0] q_m;
    logic [3:0] ones_data, ones_q;
    logic use_xnor;
    logic signed [5:0] payload_balance;
    integer bit_index;

    always_comb begin
        ones_data = 4'd0;
        for (bit_index=0; bit_index<8; bit_index=bit_index+1)
            ones_data = ones_data + {3'b000, data[bit_index]};

        // Primera etapa: seleccionar XOR/XNOR para reducir transiciones.
        use_xnor = (ones_data > 4) || ((ones_data == 4) && !data[0]);
        q_m = '0;
        q_m[0] = data[0];
        q_m[8] = !use_xnor;
        for (bit_index=1; bit_index<8; bit_index=bit_index+1) begin
            if (use_xnor)
                q_m[bit_index] = ~(q_m[bit_index-1] ^ data[bit_index]);
            else
                q_m[bit_index] = q_m[bit_index-1] ^ data[bit_index];
        end

        ones_q = 4'd0;
        for (bit_index=0; bit_index<8; bit_index=bit_index+1)
            ones_q = ones_q + {3'b000, q_m[bit_index]};
        payload_balance = $signed({1'b0, ones_q, 1'b0}) - 6'sd8;

        // Durante blanking, los controles tienen prioridad y reinician RD.
        symbol_next = CONTROL_00;
        disparity_next = 6'sd0;
        if (!de) begin
            case ({c1,c0})
                2'b00: symbol_next = 10'b1101010100;
                2'b01: symbol_next = 10'b0010101011;
                2'b10: symbol_next = 10'b0101010100;
                2'b11: symbol_next = 10'b1010101011;
                default: symbol_next = CONTROL_00;
            endcase
        end else if ((disparity == 0) || (payload_balance == 0)) begin
            // Caso canonico de empate: q_m[8] determina la inversion.
            symbol_next = {~q_m[8], q_m[8], q_m[8] ? q_m[7:0] : ~q_m[7:0]};
            if (q_m[8])
                disparity_next = disparity + payload_balance;
            else
                disparity_next = disparity - payload_balance;
        end else if (((disparity > 0) && (payload_balance > 0)) ||
                     ((disparity < 0) && (payload_balance < 0))) begin
            symbol_next = {1'b1, q_m[8], ~q_m[7:0]};
            disparity_next = disparity - payload_balance;
            if (q_m[8]) disparity_next = disparity_next + 6'sd2;
        end else begin
            symbol_next = {1'b0, q_m[8], q_m[7:0]};
            disparity_next = disparity + payload_balance;
            if (!q_m[8]) disparity_next = disparity_next - 6'sd2;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            symbol <= CONTROL_00;
            disparity <= 6'sd0;
        end else begin
            symbol <= symbol_next;
            disparity <= disparity_next;
        end
    end
endmodule
