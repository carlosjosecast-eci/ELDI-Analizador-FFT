`timescale 1ns/1ps

// Mariposa compleja compartida. Datos: 18 bits, 15 fraccionales.
// Coeficientes: 18 bits, 16 fraccionales. Cada salida incluye /2.
// Redondeo al mas cercano, empates alejandose de cero, y saturacion a 18 bits.
module fft_butterfly (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start,
    input  logic signed [17:0] a_re,
    input  logic signed [17:0] a_im,
    input  logic signed [17:0] b_re,
    input  logic signed [17:0] b_im,
    input  logic signed [17:0] w_re,
    input  logic signed [17:0] w_im,
    output logic               busy,
    output logic               done,
    output logic signed [17:0] y0_re,
    output logic signed [17:0] y0_im,
    output logic signed [17:0] y1_re,
    output logic signed [17:0] y1_im
);

    typedef enum logic [1:0] {IDLE, MULTIPLY, SUM_PRODUCTS, OUTPUTS} state_t;
    state_t state;

    logic signed [17:0] a_re_reg, a_im_reg;
    logic signed [17:0] b_re_reg, b_im_reg;
    logic signed [17:0] w_re_reg, w_im_reg;
    logic signed [35:0] product_rr, product_ii, product_ri, product_ir;
    logic signed [36:0] rotated_re, rotated_im;
    wire signed [37:0] a_re_scaled =
        $signed({{20{a_re_reg[17]}}, a_re_reg}) <<< 16;
    wire signed [37:0] a_im_scaled =
        $signed({{20{a_im_reg[17]}}, a_im_reg}) <<< 16;
    wire signed [37:0] rotated_re_wide = {rotated_re[36], rotated_re};
    wire signed [37:0] rotated_im_wide = {rotated_im[36], rotated_im};

    function automatic logic signed [17:0] round_and_saturate (
        input logic signed [37:0] value
    );
        logic signed [38:0] extended_value;
        logic [38:0] magnitude;
        logic [38:0] rounded_magnitude;
        begin
            extended_value = {value[37], value};
            if (value[37])
                magnitude = $unsigned(-extended_value);
            else
                magnitude = $unsigned(extended_value);

            // Trabajar con la magnitud hace simetricos ambos signos.
            // 2^16 es la mitad del divisor 2^17.
            rounded_magnitude = (magnitude + 39'd65536) >> 17;
            if (value[37]) begin
                if (rounded_magnitude >= 39'd131072)
                    round_and_saturate = 18'sh20000;
                else
                    round_and_saturate = -$signed(rounded_magnitude[17:0]);
            end else begin
                if (rounded_magnitude > 39'd131071)
                    round_and_saturate = 18'sh1ffff;
                else
                    round_and_saturate = $signed(rounded_magnitude[17:0]);
            end
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            a_re_reg <= '0;
            a_im_reg <= '0;
            b_re_reg <= '0;
            b_im_reg <= '0;
            w_re_reg <= '0;
            w_im_reg <= '0;
            product_rr <= '0;
            product_ii <= '0;
            product_ri <= '0;
            product_ir <= '0;
            rotated_re <= '0;
            rotated_im <= '0;
            y0_re <= '0;
            y0_im <= '0;
            y1_re <= '0;
            y1_im <= '0;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    if (start) begin
                        // Un start durante busy se ignora: los operandos
                        // aceptados se conservan durante toda la operacion.
                        a_re_reg <= a_re;
                        a_im_reg <= a_im;
                        b_re_reg <= b_re;
                        b_im_reg <= b_im;
                        w_re_reg <= w_re;
                        w_im_reg <= w_im;
                        busy <= 1'b1;
                        state <= MULTIPLY;
                    end
                end

                MULTIPLY: begin
                    product_rr <= b_re_reg * w_re_reg;
                    product_ii <= b_im_reg * w_im_reg;
                    product_ri <= b_re_reg * w_im_reg;
                    product_ir <= b_im_reg * w_re_reg;
                    state <= SUM_PRODUCTS;
                end

                SUM_PRODUCTS: begin
                    rotated_re <= $signed({product_rr[35], product_rr}) -
                                  $signed({product_ii[35], product_ii});
                    rotated_im <= $signed({product_ri[35], product_ri}) +
                                  $signed({product_ir[35], product_ir});
                    state <= OUTPUTS;
                end

                OUTPUTS: begin
                    // A se alinea con los 31 bits fraccionales del producto.
                    // Dividir al final por 2^17 alinea a 15 fraccionales y /2.
                    y0_re <= round_and_saturate(a_re_scaled + rotated_re_wide);
                    y0_im <= round_and_saturate(a_im_scaled + rotated_im_wide);
                    y1_re <= round_and_saturate(a_re_scaled - rotated_re_wide);
                    y1_im <= round_and_saturate(a_im_scaled - rotated_im_wide);
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
