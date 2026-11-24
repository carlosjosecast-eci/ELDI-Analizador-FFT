`timescale 1ns/1ps

// Integracion portable: ADC -> captura/FFT/magnitud -> bancos -> video -> TMDS.
// No contiene PLL, serializadores, pines ni programacion fisica.
// Integración de la variante de presentación. El procesamiento usa los mismos módulos.
module analyzer_core #(
    parameter integer ADC_STARTUP_CYCLES = 1_350_000,
    parameter integer DEBOUNCE_CYCLES = 1_485_000,
    parameter integer VIDEO_TEST_PATTERN = 0
) (
    input  wire clk27,
    input  wire pix_clk,
    input  wire rst27_n,
    input  wire rstpix_n,
    input  wire key_s2,
    input  wire adc_busy,
    input  wire adc_fd,
    input  wire [7:0] adc_db,
    output wire adc_convst,
    output wire adc_cs_n,
    output wire adc_rd_n,
    output wire adc_reset,
    output wire [9:0] tmds_red,
    output wire [9:0] tmds_green,
    output wire [9:0] tmds_blue,
    output wire mode_fft,
    output wire adc_fault,
    output wire processor_fault,
    output wire display_fault,
    output wire front_valid,
    output wire [31:0] front_seq,

    // Observacion publica para la unica prueba integrada; el wrapper fisico
    // puede dejar estas salidas sin conectar para que se optimicen.
    output wire [7:0] rgb_r,
    output wire [7:0] rgb_g,
    output wire [7:0] rgb_b,
    output wire video_de,
    output wire video_hsync,
    output wire video_vsync,
    output wire [10:0] pixel_x,
    output wire [9:0] pixel_y,
    output wire pixel_frame_start,
    output wire debug_sample_valid,
    output wire signed [15:0] debug_sample_signed,
    output wire debug_frame_begin,
    output wire [31:0] debug_frame_seq,
    output wire debug_wave_valid,
    output wire [7:0] debug_wave_index,
    output wire signed [15:0] debug_wave_sample,
    output wire debug_spectrum_valid,
    output wire [7:0] debug_spectrum_index,
    output wire [17:0] debug_spectrum_mag,
    output wire debug_frame_done,
    output wire debug_display_busy
);

    wire timing_de, timing_hsync, timing_vsync;
    wire [7:0] raw_r, raw_g, raw_b;
    wire raw_video_de, raw_video_hsync, raw_video_vsync;
    wire [23:0] overlay_rgb;
    wire [10:0] diag_x;
    wire [9:0] diag_y;
    wire [3:0] diag_adc_code, diag_processor_code;
    video_timing_720p timing (
        .clk(pix_clk), .rst_n(rstpix_n), .x(pixel_x), .y(pixel_y),
        .de(timing_de), .hsync(timing_hsync), .vsync(timing_vsync),
        .frame_start(pixel_frame_start)
    );
    view_selector #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) selector (
        .clk(pix_clk), .rst_n(rstpix_n), .key_s2(key_s2),
        .frame_start(pixel_frame_start), .mode_fft(mode_fft)
    );

    generate
        if (VIDEO_TEST_PATTERN == 0) begin : acquisition_video
            wire [3:0] adc_fault_code, processor_fault_code;
            assign diag_adc_code = adc_fault_code;
            assign diag_processor_code = processor_fault_code;
            wire processor_busy;
            wire rd_en, rd_valid;
            wire [7:0] rd_wave_addr, rd_spectrum_addr;
            wire signed [15:0] wave_prev, wave_sample;
            wire [17:0] spectrum_mag;

            ad7606_byte_reader #(.STARTUP_CYCLES(ADC_STARTUP_CYCLES)) adc_reader (
                .clk(clk27), .rst_n(rst27_n), .adc_busy(adc_busy),
                .adc_fd(adc_fd), .adc_db(adc_db),
                .adc_convst(adc_convst), .adc_cs_n(adc_cs_n),
                .adc_rd_n(adc_rd_n), .adc_reset(adc_reset),
                .sample_signed(debug_sample_signed), .sample_valid(debug_sample_valid),
                .fault_latched(adc_fault), .fault_code(adc_fault_code)
            );
            signal_processor processor (
                .clk(clk27), .rst_n(rst27_n),
                .sample_valid(debug_sample_valid), .sample_signed(debug_sample_signed),
                .frame_begin(debug_frame_begin), .frame_seq(debug_frame_seq),
                .wave_valid(debug_wave_valid), .wave_index(debug_wave_index),
                .wave_sample(debug_wave_sample), .spectrum_valid(debug_spectrum_valid),
                .spectrum_index(debug_spectrum_index), .spectrum_mag(debug_spectrum_mag),
                .frame_done(debug_frame_done), .busy(processor_busy),
                .fault_latched(processor_fault), .fault_code(processor_fault_code)
            );
            display_buffer display (
                .wr_clk(clk27), .wr_rst_n(rst27_n),
                .pix_clk(pix_clk), .pix_rst_n(rstpix_n), .frame_start(pixel_frame_start),
                .frame_begin(debug_frame_begin), .frame_seq(debug_frame_seq),
                .wave_valid(debug_wave_valid), .wave_index(debug_wave_index),
                .wave_sample(debug_wave_sample), .spectrum_valid(debug_spectrum_valid),
                .spectrum_index(debug_spectrum_index), .spectrum_mag(debug_spectrum_mag),
                .frame_done(debug_frame_done), .wr_busy(debug_display_busy),
                .wr_fault_latched(display_fault), .front_valid(front_valid), .front_seq(front_seq),
                .rd_en(rd_en), .rd_wave_addr(rd_wave_addr), .rd_spectrum_addr(rd_spectrum_addr),
                .rd_valid(rd_valid), .rd_wave_prev(wave_prev), .rd_wave_sample(wave_sample),
                .rd_spectrum_mag(spectrum_mag)
            );
            plot_renderer renderer (
                .clk(pix_clk), .rst_n(rstpix_n), .x(pixel_x), .y(pixel_y),
                .de(timing_de), .hsync(timing_hsync), .vsync(timing_vsync),
                .mode_fft(mode_fft), .front_valid(front_valid),
                .rd_en(rd_en), .rd_wave_addr(rd_wave_addr), .rd_spectrum_addr(rd_spectrum_addr),
                .rd_valid(rd_valid), .wave_prev(wave_prev), .wave_sample(wave_sample),
                .spectrum_mag(spectrum_mag), .rgb_r(raw_r), .rgb_g(raw_g), .rgb_b(raw_b),
                .de_out(raw_video_de), .hsync_out(raw_video_hsync), .vsync_out(raw_video_vsync)
            );
        end else begin : bars_video
            // Primera prueba fisica: barras sin depender del ADC ni de la FFT.
            // La latencia RGB/sincronismos coincide con la del renderizador.
            reg [23:0] color_q, color_out;
            reg de_q, hs_q, vs_q, de_out, hs_out, vs_out;
            function automatic [23:0] bar_color(input [10:0] x);
                begin
                    if (x < 160) bar_color = 24'hffffff;
                    else if (x < 320) bar_color = 24'hffff00;
                    else if (x < 480) bar_color = 24'h00ffff;
                    else if (x < 640) bar_color = 24'h00ff00;
                    else if (x < 800) bar_color = 24'hff00ff;
                    else if (x < 960) bar_color = 24'hff0000;
                    else if (x < 1120) bar_color = 24'h0000ff;
                    else bar_color = 24'h000000;
                end
            endfunction
            always @(posedge pix_clk or negedge rstpix_n) begin
                if (!rstpix_n) begin
                    color_q <= 0; color_out <= 0;
                    de_q <= 0; hs_q <= 0; vs_q <= 0;
                    de_out <= 0; hs_out <= 0; vs_out <= 0;
                end else begin
                    color_q <= timing_de ? bar_color(pixel_x) : 24'd0;
                    color_out <= color_q;
                    de_q <= timing_de; hs_q <= timing_hsync; vs_q <= timing_vsync;
                    de_out <= de_q; hs_out <= hs_q; vs_out <= vs_q;
                end
            end
            assign {raw_r, raw_g, raw_b} = color_out;
            assign diag_adc_code = 4'd0;
            assign diag_processor_code = 4'd0;
            assign raw_video_de = de_out;
            assign raw_video_hsync = hs_out;
            assign raw_video_vsync = vs_out;
            assign adc_convst = 1'b0;
            assign adc_cs_n = 1'b1;
            assign adc_rd_n = 1'b1;
            assign adc_reset = 1'b0;
            assign adc_fault = 1'b0;
            assign processor_fault = 1'b0;
            assign display_fault = 1'b0;
            assign front_valid = rstpix_n;
            assign front_seq = 32'd0;
            assign debug_sample_valid = 1'b0;
            assign debug_sample_signed = 16'sd0;
            assign debug_frame_begin = 1'b0;
            assign debug_frame_seq = 32'd0;
            assign debug_wave_valid = 1'b0;
            assign debug_wave_index = 8'd0;
            assign debug_wave_sample = 16'sd0;
            assign debug_spectrum_valid = 1'b0;
            assign debug_spectrum_index = 8'd0;
            assign debug_spectrum_mag = 18'd0;
            assign debug_frame_done = 1'b0;
            assign debug_display_busy = 1'b0;
        end
    endgenerate

    // Cambia únicamente las coordenadas enviadas al diagnóstico validado.
    presentation_diagnostic_layout compact_boxes (
        .x(pixel_x), .y(pixel_y), .diag_x(diag_x), .diag_y(diag_y)
    );
    diagnostic_overlay diag_overlay (
        .wr_clk27(clk27), .wr_rst_n(rst27_n),
        .pix_clk(pix_clk), .pix_rst_n(rstpix_n),
        .pixel_frame_start(pixel_frame_start), .pixel_x(diag_x), .pixel_y(diag_y),
        .video_de(raw_video_de), .in_rgb({raw_r, raw_g, raw_b}),
        .adc_fault(adc_fault), .adc_code(diag_adc_code),
        .processor_fault(processor_fault), .processor_code(diag_processor_code),
        .display_fault(display_fault), .out_rgb(overlay_rgb)
    );

    presentation_overlay annotations (
        .pixel_clk(pix_clk), .rst_n(rstpix_n),
        .x(pixel_x), .y(pixel_y), .mode(mode_fft),
        .rgb_in(overlay_rgb), .de_in(raw_video_de),
        .hsync_in(raw_video_hsync), .vsync_in(raw_video_vsync),
        .rgb_out({rgb_r, rgb_g, rgb_b}), .de_out(video_de),
        .hsync_out(video_hsync), .vsync_out(video_vsync)
    );

    // En DVI los controles HS/VS viajan por el canal azul durante blanking.
    tmds_encoder encode_red (
        .clk(pix_clk), .rst_n(rstpix_n), .de(video_de), .data(rgb_r),
        .c0(1'b0), .c1(1'b0), .symbol(tmds_red)
    );
    tmds_encoder encode_green (
        .clk(pix_clk), .rst_n(rstpix_n), .de(video_de), .data(rgb_g),
        .c0(1'b0), .c1(1'b0), .symbol(tmds_green)
    );
    tmds_encoder encode_blue (
        .clk(pix_clk), .rst_n(rstpix_n), .de(video_de), .data(rgb_b),
        .c0(video_hsync), .c1(video_vsync), .symbol(tmds_blue)
    );
endmodule
