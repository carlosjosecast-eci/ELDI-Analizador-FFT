`timescale 1ns/1ps

// Magnitud compleja entera exacta: floor(sqrt(re^2 + im^2)).
// Entrada signed18 con 15 bits fraccionales; salida unsigned18 con la misma escala.
// Captura C0, cuadrados C1, inicializacion C2, raiz restauradora C3..C20.
module fft_magnitude (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               start,
    input  logic signed [17:0] in_re,
    input  logic signed [17:0] in_im,
    output logic               busy,
    output logic               done,
    output logic [17:0]        magnitude
);

    typedef enum logic [1:0] {IDLE, SQUARE, INITIALIZE, ROOT_ITERATION} state_t;
    state_t state;

    logic signed [17:0] re_reg, im_reg;
    logic signed [35:0] square_re, square_im;
    wire [36:0] square_sum = {1'b0, $unsigned(square_re)} +
                            {1'b0, $unsigned(square_im)};
    logic [35:0] radicand_shift;
    logic [37:0] remainder;
    logic [17:0] partial_root;
    logic [4:0] iteration;

    // Se procesan los pares del radicando desde el mas significativo.
    // Todos los operandos de esta recurrencia son unsigned.
    wire [37:0] expanded_remainder =
        (remainder << 2) | {36'd0, radicand_shift[35:34]};
    wire [37:0] trial_divisor = ({20'd0, partial_root} << 2) | 38'd1;
    wire take_bit = expanded_remainder >= trial_divisor;
    wire [37:0] next_remainder = take_bit
        ? expanded_remainder - trial_divisor : expanded_remainder;
    wire [17:0] next_root = {partial_root[16:0], take_bit};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            re_reg <= '0;
            im_reg <= '0;
            square_re <= '0;
            square_im <= '0;
            radicand_shift <= '0;
            remainder <= '0;
            partial_root <= '0;
            iteration <= '0;
            busy <= 1'b0;
            done <= 1'b0;
            magnitude <= '0;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    if (start) begin
                        re_reg <= in_re;
                        im_reg <= in_im;
                        busy <= 1'b1;
                        state <= SQUARE;
                    end
                end

                SQUARE: begin
                    // Cada cuadrado cabe en signed36, incluso (-131072)^2.
                    square_re <= re_reg * re_reg;
                    square_im <= im_reg * im_reg;
                    state <= INITIALIZE;
                end

                INITIALIZE: begin
                    // S maximo=2^35; los 36 bits unsigned bastan para la suma.
                    radicand_shift <= square_sum[35:0];
                    remainder <= '0;
                    partial_root <= '0;
                    iteration <= '0;
                    state <= ROOT_ITERATION;
                end

                ROOT_ITERATION: begin
                    radicand_shift <= {radicand_shift[33:0], 2'b00};
                    remainder <= next_remainder;
                    partial_root <= next_root;
                    if (iteration == 5'd17) begin
                        // Tras 18 pares, next_root es la raiz entera por defecto.
                        // Usar next_root evita publicar el resultado de 17 pasos.
                        magnitude <= next_root;
                        busy <= 1'b0;
                        done <= 1'b1;
                        state <= IDLE;
                    end else begin
                        iteration <= iteration + 1'b1;
                    end
                end
            endcase
        end
    end
endmodule
