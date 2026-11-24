`timescale 1ns/1ps

// Generador RGB sin framebuffer. Dominio de pixel: 74,25 MHz.
// E0: RAM acepta direccion y este modulo guarda coordenadas/sincronismos.
// E1: usa el dato de esa RAM y publica RGB/sincronismos de ese mismo pixel.
module plot_renderer (
    input  wire               clk,
    input  wire               rst_n,
    input  wire [10:0]        x,
    input  wire [9:0]         y,
    input  wire               de,
    input  wire               hsync,
    input  wire               vsync,
    input  wire               mode_fft,
    input  wire               front_valid,

    output wire               rd_en,
    output reg [7:0]          rd_wave_addr,
    output reg [7:0]          rd_spectrum_addr,
    input  wire               rd_valid,
    input  wire signed [15:0] wave_prev,
    input  wire signed [15:0] wave_sample,
    input  wire [17:0]        spectrum_mag,

    output reg [7:0]          rgb_r,
    output reg [7:0]          rgb_g,
    output reg [7:0]          rgb_b,
    output reg                de_out,
    output reg                hsync_out,
    output reg                vsync_out
);

    localparam [23:0] COLOR_BLACK = 24'h000000;
    localparam [23:0] COLOR_GRID = 24'h202020;
    localparam [23:0] COLOR_AXIS = 24'h606060;
    localparam [23:0] COLOR_BORDER = 24'h808080;
    localparam [23:0] COLOR_WAVE = 24'h00ff40;
    localparam [23:0] COLOR_FFT = 24'h00d8ff;

    reg [10:0] x_q;
    reg [9:0] y_q;
    reg de_q, hsync_q, vsync_q, mode_q, front_q;
    reg [23:0] pixel_color;
    reg plot_x, plot_y, grid_pixel, axis_pixel, border_pixel, data_pixel;
    reg [9:0] current_y, previous_y;
    reg [9:0] bar_height;
    wire [10:0] x_offset = x - 11'd128;

    assign rd_en = rst_n && de && front_valid;

    // Se leen ambos bancos de datos con una unica habilitacion. Fuera del
    // intervalo de la grafica, las direcciones se recortan a un extremo valido.
    always @* begin
        if (x < 11'd128)
            rd_wave_addr = 8'd0;
        else if (x > 11'd1151)
            rd_wave_addr = 8'd255;
        else
            rd_wave_addr = x_offset[9:2];

        if (x < 11'd128)
            rd_spectrum_addr = 8'd0;
        else if (x > 11'd1159)
            rd_spectrum_addr = 8'd128;
        else
            rd_spectrum_addr = x_offset[10:3];
    end

    function automatic [9:0] sample_to_y(input signed [15:0] sample_value);
        integer signed sample_integer;
        integer signed screen_y;
        begin
            sample_integer = $signed(sample_value);
            screen_y = 384 - (sample_integer >>> 7);
            if (screen_y < 128)
                sample_to_y = 10'd128;
            else if (screen_y > 639)
                sample_to_y = 10'd639;
            else
                sample_to_y = screen_y[9:0];
        end
    endfunction

    always @* begin
        plot_x = (x_q >= 11'd128) &&
                 (mode_q ? (x_q <= 11'd1159) : (x_q <= 11'd1151));
        plot_y = (y_q >= 10'd128) && (y_q <= 10'd639);

        grid_pixel = plot_x && plot_y &&
                     ((x_q[6:0] == 7'd0) || (y_q[6:0] == 7'd0));
        axis_pixel = plot_x && plot_y &&
                     ((x_q == 11'd128) ||
                      (mode_q ? (y_q == 10'd639) : (y_q == 10'd384)));
        border_pixel =
            (((x_q == 11'd127) ||
              (mode_q ? (x_q == 11'd1160) : (x_q == 11'd1152))) &&
             (y_q >= 10'd127) && (y_q <= 10'd640)) ||
            (((y_q == 10'd127) || (y_q == 10'd640)) &&
             (x_q >= 11'd127) &&
             (mode_q ? (x_q <= 11'd1160) : (x_q <= 11'd1152)));

        current_y = sample_to_y(wave_sample);
        previous_y = sample_to_y(wave_prev);
        // Mantener unsigned es imprescindible: 185363 no cabe en signed18.
        if (spectrum_mag >= 18'd32768)
            bar_height = 10'd511;
        else
            bar_height = {1'b0, spectrum_mag[14:6]};

        data_pixel = 1'b0;
        if (front_q && rd_valid && plot_x && plot_y) begin
            if (mode_q) begin
                data_pixel = (bar_height != 10'd0) &&
                             (y_q >= (10'd640 - bar_height));
            end else if (x_q[1:0] != 2'b00) begin
                data_pixel = (y_q == current_y);
            end else begin
                // Primer pixel de cada grupo: union vertical de dos muestras.
                // display_buffer entrega prev=current para el primer indice.
                data_pixel = ((y_q >= previous_y) && (y_q <= current_y)) ||
                             ((y_q >= current_y) && (y_q <= previous_y));
            end
        end

        pixel_color = COLOR_BLACK;
        if (de_q) begin
            if (data_pixel)
                pixel_color = mode_q ? COLOR_FFT : COLOR_WAVE;
            else if (axis_pixel)
                pixel_color = COLOR_AXIS;
            else if (border_pixel)
                pixel_color = COLOR_BORDER;
            else if (grid_pixel)
                pixel_color = COLOR_GRID;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_q <= 11'd0;
            y_q <= 10'd0;
            de_q <= 1'b0;
            hsync_q <= 1'b0;
            vsync_q <= 1'b0;
            mode_q <= 1'b0;
            front_q <= 1'b0;
            rgb_r <= 8'd0;
            rgb_g <= 8'd0;
            rgb_b <= 8'd0;
            de_out <= 1'b0;
            hsync_out <= 1'b0;
            vsync_out <= 1'b0;
        end else begin
            x_q <= x;
            y_q <= y;
            de_q <= de;
            hsync_q <= hsync;
            vsync_q <= vsync;
            mode_q <= mode_fft;
            front_q <= front_valid;

            {rgb_r, rgb_g, rgb_b} <= pixel_color;
            de_out <= de_q;
            hsync_out <= hsync_q;
            vsync_out <= vsync_q;
        end
    end

endmodule
