`timescale 1ns/1ps

// Reutiliza las comparaciones del diagnóstico original con casillas de 12×12.
module presentation_diagnostic_layout (
    input wire [10:0] x,
    input wire [9:0] y,
    output reg [10:0] diag_x,
    output wire [9:0] diag_y
);
    wire inside_box = (x >= 11'd128) && (x < 11'd256) && (x[3:0] < 4'd12) &&
                      (y >= 10'd103) && (y < 10'd115);
    assign diag_y = inside_box ? 10'd48 : 10'd0;

    always @* begin
        // Una coordenada por cada casilla del diagnóstico validado.
        case (x[6:4])
            3'd0: diag_x = 11'd128;
            3'd1: diag_x = 11'd208;
            3'd2: diag_x = 11'd288;
            3'd3: diag_x = 11'd368;
            3'd4: diag_x = 11'd448;
            3'd5: diag_x = 11'd528;
            3'd6: diag_x = 11'd608;
            default: diag_x = 11'd688;
        endcase
    end
endmodule

// Las anotaciones se sitúan fuera de la cuadrícula del renderer original.
module presentation_overlay (
    input wire pixel_clk,
    input wire rst_n,
    input wire [10:0] x,
    input wire [9:0] y,
    input wire mode,
    input wire [23:0] rgb_in,
    input wire de_in, hsync_in, vsync_in,
    output reg [23:0] rgb_out,
    output reg de_out, hsync_out, vsync_out
);
    localparam [3:0] NONE = 0, PROJECT = 1, TITLE = 2, AUTHORS = 3,
                     TIME_AXIS = 5, FREQ_AXIS = 6, ZERO = 7,
                     TIME_1 = 8, TIME_2 = 9, TIME_3 = 10, TIME_4 = 11,
                     FREQ_1 = 12, FREQ_2 = 13, FREQ_3 = 14, FREQ_4 = 15;

    function automatic [7:0] character_at(input [3:0] line, input [5:0] column);
        reg [511:0] line_data;
        begin
            // Alineadas al MSB. Cada carácter ocupa una posición de ocho bits.
            case (line)
                PROJECT:   line_data = {"Proyecto final ELDI", 360'd0};
                TITLE:     line_data = {"Analizador FFT", 400'd0};
                AUTHORS:   line_data = {"Carlos Jose Castiblanco / Jarid Camilo Ojeda", 160'd0};
                TIME_AXIS: line_data = {"Tiempo (ms)", 424'd0};
                FREQ_AXIS: line_data = {"Frecuencia (kHz)", 384'd0};
                ZERO:      line_data = {"0", 504'd0};
                TIME_1:    line_data = {"0,32", 480'd0};
                TIME_2:    line_data = {"0,64", 480'd0};
                TIME_3:    line_data = {"0,96", 480'd0};
                TIME_4:    line_data = {"1,275", 472'd0};
                FREQ_1:    line_data = {"25", 496'd0};
                FREQ_2:    line_data = {"50", 496'd0};
                FREQ_3:    line_data = {"75", 496'd0};
                FREQ_4:    line_data = {"100", 488'd0};
                default:   line_data = 512'd0;
            endcase
            character_at = line_data[{~column, 3'b000} +: 8];
        end
    endfunction

    reg [3:0] line;
    reg [10:0] x_text_start;
    reg [9:0] y_text_start;
    reg title_scale;
    always @* begin
        line = NONE;
        x_text_start = 11'd128;
        y_text_start = 10'd18;
        title_scale = 1'b0;

        if ((y >= 10'd18) && (y < 10'd32) && (x >= 11'd128) && (x < 11'd432)) begin
            line = PROJECT;
        end else if ((y >= 10'd40) && (y < 10'd68) && (x >= 11'd128) && (x < 11'd576)) begin
            line = TITLE;
            y_text_start = 10'd40;
            title_scale = 1'b1;
        end else if ((y >= 10'd82) && (y < 10'd96) && (x >= 11'd128) && (x < 11'd832)) begin
            line = AUTHORS;
            y_text_start = 10'd82;
        end else if ((y >= 10'd656) && (y < 10'd670)) begin
            y_text_start = 10'd656;
            if ((x >= 11'd123) && (x < 11'd139)) begin
                line = ZERO;
                x_text_start = 11'd123;
            end else if ((x >= 11'd352) && (x < 11'd416)) begin
                line = mode ? FREQ_1 : TIME_1;
                x_text_start = mode ? 11'd371 : 11'd355;
            end else if ((x >= 11'd608) && (x < 11'd672)) begin
                line = mode ? FREQ_2 : TIME_2;
                x_text_start = mode ? 11'd627 : 11'd611;
            end else if ((x >= 11'd864) && (x < 11'd928)) begin
                line = mode ? FREQ_3 : TIME_3;
                x_text_start = mode ? 11'd883 : 11'd867;
            end else if ((x >= 11'd1111) && (x < 11'd1192)) begin
                line = mode ? FREQ_4 : TIME_4;
                x_text_start = mode ? 11'd1131 : 11'd1111;
            end
        end else if ((y >= 10'd690) && (y < 10'd704)) begin
            line = mode ? FREQ_AXIS : TIME_AXIS;
            x_text_start = mode ? 11'd516 : 11'd552;
            y_text_start = 10'd690;
        end
    end

    wire [10:0] text_dx = x - x_text_start;
    wire [9:0] text_dy = y - y_text_start;
    wire [10:0] label_extent = (line == FREQ_AXIS) ? 11'd256 : 11'd176;
    wire text_valid = (line != NONE) && (x >= x_text_start) &&
        (!(line == TIME_AXIS || line == FREQ_AXIS) || (text_dx < label_extent));

    wire tick = (y >= 10'd642) && (y <= 10'd648) &&
        (x == 11'd128 || x == 11'd384 || x == 11'd640 || x == 11'd896 ||
         x == (mode ? 11'd1152 : 11'd1148));
    wire logo_region = (x >= 11'd936) && (x < 11'd1160) && (y >= 10'd8) && (y < 10'd120);
    wire [1:0] logo_level;
    presentation_logo logo (
        .clk(pixel_clk), .x(x[7:0] - 8'd168), .y(y[6:0] - 7'd8), .level(logo_level)
    );

    reg [3:0] line_0;
    reg [5:0] char_col_0;
    reg [2:0] glyph_col_0, glyph_row_0, glyph_col_1, glyph_row_1;
    reg tick_0, tick_1, tick_2;
    reg logo_0;
    reg [1:0] logo_1, logo_2;
    reg [7:0] character_1;
    reg title_1, title_2, text_2;
    reg [23:0] rgb_2;
    reg de_2, hs_2, vs_2;
    wire [4:0] row_pixels;
    presentation_font font_rom (.character(character_1), .row(glyph_row_1), .pixels(row_pixels));

    always @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            line_0 <= NONE;
            char_col_0 <= 0;
            glyph_col_0 <= 0; glyph_row_0 <= 0;
            glyph_col_1 <= 0; glyph_row_1 <= 0;
            character_1 <= 0;
            tick_0 <= 0; tick_1 <= 0; tick_2 <= 0;
            logo_0 <= 0; logo_1 <= 0; logo_2 <= 0;
            title_1 <= 0; title_2 <= 0; text_2 <= 0;
            rgb_2 <= 0; de_2 <= 0; hs_2 <= 0; vs_2 <= 0;
            rgb_out <= 0; de_out <= 0; hsync_out <= 0; vsync_out <= 0;
        end else begin
            // E0: elegir línea, columna de carácter y fila/columna del glifo.
            line_0 <= text_valid ? line : NONE;
            char_col_0 <= title_scale ? text_dx[10:5] : text_dx[9:4];
            glyph_col_0 <= title_scale ? text_dx[4:2] : text_dx[3:1];
            glyph_row_0 <= title_scale ? text_dy[4:2] : text_dy[3:1];
            logo_0 <= logo_region;
            tick_0 <= tick;

            // E1: lectura de caracteres. En este ciclo llegan RGB/DE del renderer.
            character_1 <= character_at(line_0, char_col_0);
            glyph_col_1 <= glyph_col_0;
            glyph_row_1 <= glyph_row_0;
            title_1 <= line_0 == TITLE;
            logo_1 <= logo_0 ? logo_level : 2'd0;
            tick_1 <= tick_0;

            // E2: escoger el bit del glifo y registrar todo el video en paralelo.
            text_2 <= glyph_col_1 < 3'd5 && row_pixels[3'd4 - glyph_col_1];
            title_2 <= title_1;
            logo_2 <= logo_1;
            tick_2 <= tick_1;
            rgb_2 <= rgb_in;
            de_2 <= de_in; hs_2 <= hsync_in; vs_2 <= vsync_in;

            // E3: componer la capa sin alterar los píxeles de la gráfica.
            if (!de_2) rgb_out <= 24'h000000;
            else if (logo_2 == 2'd3) rgb_out <= 24'hffffff;
            else if (logo_2 == 2'd2) rgb_out <= 24'h9aa3af;
            else if (logo_2 == 2'd1) rgb_out <= 24'h454a52;
            else if (text_2 && title_2) rgb_out <= 24'he8eef6;
            else if (text_2) rgb_out <= 24'hacb8c8;
            else if (tick_2) rgb_out <= 24'h758498;
            else rgb_out <= rgb_2;
            de_out <= de_2; hsync_out <= hs_2; vsync_out <= vs_2;
        end
    end
endmodule
