`timescale 1ns/1ps

// Captura, copia y procesa un bloque de 256 muestras a 27 MHz.
// Los flujos de salida no admiten contrapresion. No incluye memoria de pantalla.
module signal_processor (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_valid,
    input  wire signed [15:0] sample_signed,

    output wire               frame_begin,
    output reg [31:0]         frame_seq,
    output wire               wave_valid,
    output reg [7:0]          wave_index,
    output reg signed [15:0]  wave_sample,
    output wire               spectrum_valid,
    output reg [7:0]          spectrum_index,
    output reg [17:0]         spectrum_mag,
    output wire               frame_done,
    output wire               busy,
    output reg                fault_latched,
    output reg [3:0]          fault_code
);

    typedef enum logic [3:0] {
        WAIT_BLOCK, CAPTURE_REQ, CAPTURE_WAIT, SEND_INPUT, START_FFT,
        WAIT_FFT, BIN_REQ, BIN_WAIT, START_MAG, WAIT_MAG, FAILED
    } state_t;
    state_t state;

    reg saved_bank;
    reg [7:0] copy_index;
    reg signed [15:0] sample_hold;
    reg [7:0] bin_index;
    reg signed [17:0] bin_re_hold, bin_im_hold;
    reg frame_begin_q, wave_valid_q, spectrum_valid_q, frame_done_q, busy_q;

    wire capture_valid, capture_bank, capture_overrun;
    wire [31:0] capture_seq;
    wire capture_rd_valid;
    wire signed [15:0] capture_rd_sample;
    wire fft_in_ready, fft_frame_loaded, fft_busy, fft_done;
    wire fft_results_ready, fft_rd_valid, fft_fault;
    wire signed [17:0] fft_rd_re, fft_rd_im;
    wire [3:0] fft_fault_code;
    wire magnitude_busy, magnitude_done;
    wire [17:0] magnitude_value;

    // La inhibicion combinacional tambien anula strobes si un hijo anuncia
    // fallo en el mismo flanco; el registro de fallo propio lo retiene despues.
    wire abort_now = fault_latched || capture_overrun || fft_fault;
    wire capture_rd_en = (state == CAPTURE_REQ) && !abort_now;
    wire fft_in_valid = (state == SEND_INPUT) && !abort_now;
    wire fft_start = (state == START_FFT) && !abort_now;
    wire capture_release = fft_start;
    wire fft_rd_en = (state == BIN_REQ) && !abort_now;
    wire magnitude_start = (state == START_MAG) && !abort_now;

    assign frame_begin = frame_begin_q && !abort_now;
    assign wave_valid = wave_valid_q && !abort_now;
    assign spectrum_valid = spectrum_valid_q && !abort_now;
    assign frame_done = frame_done_q && !abort_now;
    assign busy = busy_q && !abort_now;

    sample_capture capture (
        .clk(clk), .rst_n(rst_n),
        .sample_valid(sample_valid), .sample_signed(sample_signed),
        .block_valid(capture_valid), .block_bank(capture_bank),
        .block_seq(capture_seq), .block_release(capture_release),
        .overrun_latched(capture_overrun),
        .rd_en(capture_rd_en), .rd_bank(saved_bank), .rd_addr(copy_index),
        .rd_sample(capture_rd_sample), .rd_valid(capture_rd_valid)
    );

    fft256_core fft (
        .clk(clk), .rst_n(rst_n),
        .in_valid(fft_in_valid), .in_sample(sample_hold), .in_ready(fft_in_ready),
        .start(fft_start), .frame_loaded(fft_frame_loaded),
        .busy(fft_busy), .done(fft_done), .results_ready(fft_results_ready),
        .rd_en(fft_rd_en), .rd_addr(bin_index),
        .rd_re(fft_rd_re), .rd_im(fft_rd_im), .rd_valid(fft_rd_valid),
        .fault_latched(fft_fault), .fault_code(fft_fault_code)
    );

    fft_magnitude magnitude_unit (
        .clk(clk), .rst_n(rst_n), .start(magnitude_start),
        .in_re(bin_re_hold), .in_im(bin_im_hold),
        .busy(magnitude_busy), .done(magnitude_done), .magnitude(magnitude_value)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= WAIT_BLOCK;
            saved_bank <= 1'b0;
            copy_index <= 8'd0;
            sample_hold <= 16'sd0;
            bin_index <= 8'd0;
            bin_re_hold <= 18'sd0;
            bin_im_hold <= 18'sd0;
            frame_begin_q <= 1'b0;
            wave_valid_q <= 1'b0;
            spectrum_valid_q <= 1'b0;
            frame_done_q <= 1'b0;
            busy_q <= 1'b0;
            frame_seq <= 32'd0;
            wave_index <= 8'd0;
            wave_sample <= 16'sd0;
            spectrum_index <= 8'd0;
            spectrum_mag <= 18'd0;
            fault_latched <= 1'b0;
            fault_code <= 4'd0;
        end else begin
            // Todos los eventos son pulsos de un ciclo. Los datos asociados
            // retienen su ultimo valor y solo se interpretan con su valid.
            frame_begin_q <= 1'b0;
            wave_valid_q <= 1'b0;
            spectrum_valid_q <= 1'b0;
            frame_done_q <= 1'b0;

            if (fault_latched) begin
                busy_q <= 1'b0;
                state <= FAILED;
            end else if (capture_overrun || fft_fault) begin
                fault_latched <= 1'b1;
                // Primera causa retenida; captura gana si aparecen a la vez.
                fault_code <= capture_overrun ? 4'd1 : 4'd2;
                busy_q <= 1'b0;
                state <= FAILED;
            end else begin
                case (state)
                    WAIT_BLOCK: begin
                        busy_q <= 1'b0;
                        if (capture_valid) begin
                            saved_bank <= capture_bank;
                            frame_seq <= capture_seq;
                            copy_index <= 8'd0;
                            frame_begin_q <= 1'b1;
                            busy_q <= 1'b1;
                            state <= CAPTURE_REQ;
                        end
                    end

                    CAPTURE_REQ: begin
                        // Este flanco solicita una lectura sincrona de captura.
                        state <= CAPTURE_WAIT;
                    end
                    CAPTURE_WAIT: begin
                        if (capture_rd_valid) begin
                            sample_hold <= capture_rd_sample;
                            state <= SEND_INPUT;
                        end
                    end
                    SEND_INPUT: begin
                        // sample_hold e in_valid permanecen estables si ready
                        // tarda. Solo el handshake genera la muestra de traza.
                        if (fft_in_ready) begin
                            wave_valid_q <= 1'b1;
                            wave_index <= copy_index;
                            wave_sample <= sample_hold;
                            if (copy_index == 8'd255) begin
                                state <= START_FFT;
                            end else begin
                                copy_index <= copy_index + 8'd1;
                                state <= CAPTURE_REQ;
                            end
                        end
                    end

                    START_FFT: begin
                        // Este flanco es POSTERIOR al handshake de muestra255:
                        // frame_loaded ya esta alto. start y release son los
                        // pulsos combinacionales de este estado, no del anterior.
                        state <= WAIT_FFT;
                    end
                    WAIT_FFT: begin
                        if (fft_done) begin
                            bin_index <= 8'd0;
                            state <= BIN_REQ;
                        end
                    end

                    BIN_REQ: begin
                        state <= BIN_WAIT;
                    end
                    BIN_WAIT: begin
                        if (fft_rd_valid) begin
                            bin_re_hold <= fft_rd_re;
                            bin_im_hold <= fft_rd_im;
                            state <= START_MAG;
                        end
                    end
                    START_MAG: begin
                        // Re/Im quedaron registrados en el flanco anterior.
                        state <= WAIT_MAG;
                    end
                    WAIT_MAG: begin
                        if (magnitude_done) begin
                            spectrum_valid_q <= 1'b1;
                            spectrum_index <= bin_index;
                            spectrum_mag <= magnitude_value;
                            if (bin_index == 8'd128) begin
                                frame_done_q <= 1'b1;
                                busy_q <= 1'b0;
                                state <= WAIT_BLOCK;
                            end else begin
                                bin_index <= bin_index + 8'd1;
                                state <= BIN_REQ;
                            end
                        end
                    end
                    FAILED: begin
                        busy_q <= 1'b0;
                    end
                    default: begin
                        busy_q <= 1'b0;
                        state <= WAIT_BLOCK;
                    end
                endcase
            end
        end
    end

endmodule
