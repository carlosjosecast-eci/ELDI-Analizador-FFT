`timescale 1ns/1ps

// FFT256 radix-2 DIT iterativa, una mariposa compartida y memoria de un puerto.
// Entrada natural real signed16/Q1.15; escritura con inversion de bits.
// Datos internos signed18 con 15 fraccionales; salida natural FFT/256.
module fft256_core (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               in_valid,
    input  logic signed [15:0] in_sample,
    output wire                in_ready,
    input  logic               start,
    output logic               frame_loaded,
    output logic               busy,
    output logic               done,
    output logic               results_ready,
    input  logic               rd_en,
    input  logic [7:0]         rd_addr,
    output wire signed [17:0]  rd_re,
    output wire signed [17:0]  rd_im,
    output logic               rd_valid,
    output logic               fault_latched,
    output logic [3:0]         fault_code
);

    typedef enum logic [2:0] {
        IDLE, READ_A, READ_B, BF_START, BF_WAIT, WRITE_A, WRITE_B
    } state_t;
    state_t state;

    logic [7:0] load_index;
    logic [2:0] stage_index;
    logic [7:0] group_base;
    logic [6:0] pair_index;
    wire [8:0] half_span = 9'd1 << stage_index;
    wire [8:0] group_span = 9'd2 << stage_index;
    wire [8:0] group_end = {1'b0, group_base} + group_span;
    wire [8:0] address_a_wide = {1'b0, group_base} + {2'b00, pair_index};
    wire [8:0] address_b_wide = address_a_wide + half_span;
    wire [7:0] address_a = address_a_wide[7:0];
    wire [7:0] address_b = address_b_wide[7:0];
    wire [6:0] twiddle_addr = pair_index << (3'd7 - stage_index);

    wire input_accept = in_valid && in_ready;
    wire result_read_accept = rd_en && results_ready && !busy &&
                              !input_accept && !start && !fault_latched;
    wire fault_pending = start && (busy || !frame_loaded);
    wire [3:0] pending_fault_code = busy ? 4'd2 : 4'd1;

    // Un unico puerto fisico: direccion, dato y habilitaciones centralizados.
    // Memoria y registro de lectura SIN reset para permitir inferencia BSRAM.
    logic [35:0] memory [0:255];
    logic [35:0] memory_q;
    logic memory_en, memory_we;
    logic [7:0] memory_addr;
    logic [35:0] memory_d;

    logic signed [17:0] operand_a_re, operand_a_im;
    wire signed [17:0] twiddle_re, twiddle_im;
    wire signed [17:0] result_a_re, result_a_im, result_b_re, result_b_im;
    wire butterfly_busy, butterfly_done;
    wire butterfly_start = (state == BF_START) && !fault_latched && !fault_pending;
    wire twiddle_en = (state == READ_A) && !fault_latched && !fault_pending;

    assign in_ready = rst_n && !busy && !frame_loaded && !fault_latched;
    // memory_q es el registro sincrono de salida del unico puerto.
    // Solo interpretar estos datos cuando rd_valid este alto.
    assign rd_re = $signed(memory_q[35:18]);
    assign rd_im = $signed(memory_q[17:0]);

    function automatic logic [7:0] reverse_bits(input logic [7:0] value);
        integer bit_index;
        begin
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                reverse_bits[bit_index] = value[7-bit_index];
        end
    endfunction

    fft_twiddle_rom twiddles (
        .clk(clk), .en(twiddle_en), .addr(twiddle_addr),
        .w_re(twiddle_re), .w_im(twiddle_im)
    );

    fft_butterfly butterfly (
        .clk(clk), .rst_n(rst_n), .start(butterfly_start),
        .a_re(operand_a_re), .a_im(operand_a_im),
        .b_re($signed(memory_q[35:18])), .b_im($signed(memory_q[17:0])),
        .w_re(twiddle_re), .w_im(twiddle_im),
        .busy(butterfly_busy), .done(butterfly_done),
        .y0_re(result_a_re), .y0_im(result_a_im),
        .y1_re(result_b_re), .y1_im(result_b_im)
    );

    always_comb begin
        memory_en = 1'b0;
        memory_we = 1'b0;
        memory_addr = '0;
        memory_d = '0;

        if (rst_n && !fault_latched && !fault_pending) begin
            case (state)
                IDLE: begin
                    if (input_accept) begin
                        memory_en = 1'b1;
                        memory_we = 1'b1;
                        memory_addr = reverse_bits(load_index);
                        memory_d = {{2{in_sample[15]}}, in_sample, 18'd0};
                    end else if (result_read_accept) begin
                        memory_en = 1'b1;
                        memory_addr = rd_addr;
                    end
                end
                READ_A: begin
                    memory_en = 1'b1;
                    memory_addr = address_a;
                end
                READ_B: begin
                    memory_en = 1'b1;
                    memory_addr = address_b;
                end
                WRITE_A: begin
                    memory_en = 1'b1;
                    memory_we = 1'b1;
                    memory_addr = address_a;
                    memory_d = {result_a_re, result_a_im};
                end
                WRITE_B: begin
                    memory_en = 1'b1;
                    memory_we = 1'b1;
                    memory_addr = address_b;
                    memory_d = {result_b_re, result_b_im};
                end
                default: begin end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (memory_en) begin
            if (memory_we)
                memory[memory_addr] <= memory_d;
            else
                memory_q <= memory[memory_addr];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            load_index <= '0;
            stage_index <= '0;
            group_base <= '0;
            pair_index <= '0;
            operand_a_re <= '0;
            operand_a_im <= '0;
            frame_loaded <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            results_ready <= 1'b0;
            rd_valid <= 1'b0;
            fault_latched <= 1'b0;
            fault_code <= 4'd0;
        end else begin
            done <= 1'b0;
            rd_valid <= 1'b0;

            if (fault_latched || fault_pending) begin
                // El fallo cancela accesos y publicacion. Si la mariposa
                // interna estaba trabajando, su resultado se ignora.
                state <= IDLE;
                busy <= 1'b0;
                frame_loaded <= 1'b0;
                results_ready <= 1'b0;
                if (!fault_latched) begin
                    fault_latched <= 1'b1;
                    fault_code <= pending_fault_code;
                end
            end else begin
                case (state)
                    IDLE: begin
                        rd_valid <= result_read_accept;
                        if (start) begin
                            // Llegar aqui con start implica un bloque completo.
                            busy <= 1'b1;
                            frame_loaded <= 1'b0;
                            results_ready <= 1'b0;
                            load_index <= '0;
                            stage_index <= '0;
                            group_base <= '0;
                            pair_index <= '0;
                            state <= READ_A;
                        end else if (input_accept) begin
                            // La primera muestra nueva invalida la FFT anterior.
                            results_ready <= 1'b0;
                            if (load_index == 8'd255) begin
                                frame_loaded <= 1'b1;
                            end else begin
                                load_index <= load_index + 1'b1;
                            end
                        end
                    end

                    READ_A: begin
                        // Este flanco solicita A y el coeficiente a sus RAM/ROM.
                        state <= READ_B;
                    end
                    READ_B: begin
                        // memory_q contiene A; este flanco solicita B.
                        operand_a_re <= $signed(memory_q[35:18]);
                        operand_a_im <= $signed(memory_q[17:0]);
                        state <= BF_START;
                    end
                    BF_START: begin
                        // A ya esta registrado, memory_q contiene B y W es valido.
                        state <= BF_WAIT;
                    end
                    BF_WAIT: begin
                        if (butterfly_done)
                            state <= WRITE_A;
                    end
                    WRITE_A: begin
                        state <= WRITE_B;
                    end
                    WRITE_B: begin
                        // Este flanco escribe B y avanza grupo/par/etapa.
                        if ({2'b00, pair_index} == half_span - 9'd1) begin
                            pair_index <= '0;
                            if (group_end == 9'd256) begin
                                group_base <= '0;
                                if (stage_index == 3'd7) begin
                                    busy <= 1'b0;
                                    done <= 1'b1;
                                    results_ready <= 1'b1;
                                    state <= IDLE;
                                end else begin
                                    stage_index <= stage_index + 1'b1;
                                    state <= READ_A;
                                end
                            end else begin
                                group_base <= group_end[7:0];
                                state <= READ_A;
                            end
                        end else begin
                            pair_index <= pair_index + 1'b1;
                            state <= READ_A;
                        end
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule
