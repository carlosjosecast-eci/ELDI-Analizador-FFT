`timescale 1ns/1ps

// Instrumento temporal para identificar la primera causa del fallo fisico.
// No cambia el protocolo ADC ni agrega una etapa de latencia al video.
module diagnostic_overlay (
    input  wire        wr_clk27,
    input  wire        wr_rst_n,
    input  wire        pix_clk,
    input  wire        pix_rst_n,
    input  wire        pixel_frame_start,
    input  wire [10:0] pixel_x,
    input  wire [9:0]  pixel_y,
    input  wire        video_de,
    input  wire [23:0] in_rgb,
    input  wire        adc_fault,
    input  wire [3:0]  adc_code,
    input  wire        processor_fault,
    input  wire [3:0]  processor_code,
    input  wire        display_fault,
    output wire [23:0] out_rgb
);

    // Nombres conservados para identificar las rutas CDC en el SDC diagnostico.
    // code_hold queda estable desde first_valid hasta el reset coordinado.
    (* syn_preserve = 1 *) reg [3:0] code_hold;
    (* syn_preserve = 1 *) reg first_valid;
    (* syn_preserve = 1 *) reg valid_meta;
    (* syn_preserve = 1 *) reg valid_sync;
    (* syn_preserve = 1 *) reg [3:0] code_pix;
    reg pixel_code_captured;
    reg [10:0] pixel_x_d1, pixel_x_d2;
    reg [9:0] pixel_y_d1, pixel_y_d2;

    always @(posedge wr_clk27 or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            code_hold <= 4'd0;
            first_valid <= 1'b0;
        end else if (!first_valid) begin
            // Si coinciden en un flanco, ADC tiene prioridad sobre procesador
            // y este sobre display. Una causa ya retenida nunca se reemplaza.
            if (adc_fault) begin
                code_hold <= adc_code; // Codigos originales ADC: 1..5.
                first_valid <= 1'b1;
            end else if (processor_fault) begin
                // El procesador solo emite 1 (captura) o 2 (FFT).
                code_hold <= (processor_code == 4'd1) ? 4'd6 : 4'd7;
                first_valid <= 1'b1;
            end else if (display_fault) begin
                code_hold <= 4'd8;
                first_valid <= 1'b1;
            end
        end
    end

    // Solo el aviso de validez atraviesa dos FF. Los cuatro bits de codigo
    // son un bus estatico asociado; no se sincronizan independientemente.
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            valid_meta <= 1'b0;
            valid_sync <= 1'b0;
        end else begin
            valid_meta <= first_valid;
            valid_sync <= valid_meta;
        end
    end

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            code_pix <= 4'd0;
            pixel_code_captured <= 1'b0;
            pixel_x_d1 <= 11'd0;
            pixel_x_d2 <= 11'd0;
            pixel_y_d1 <= 10'd0;
            pixel_y_d2 <= 10'd0;
        end else begin
            // El renderizador entrega RGB tras E0/E1: dos registros de
            // coordenadas dejan el recuadro alineado con ese mismo pixel.
            pixel_x_d1 <= pixel_x;
            pixel_x_d2 <= pixel_x_d1;
            pixel_y_d1 <= pixel_y;
            pixel_y_d2 <= pixel_y_d1;
            if (pixel_frame_start && valid_sync && !pixel_code_captured) begin
                code_pix <= code_hold;
                pixel_code_captured <= 1'b1;
            end
        end
    end

    // Ocho comparaciones constantes, sin fuentes ni division por 80.
    wire row_match = (pixel_y_d2 >= 10'd48) && (pixel_y_d2 <= 10'd79);
    wire [7:0] box_match;
    wire [7:0] red_match;
    genvar box_index;
    generate
        for (box_index = 0; box_index < 8; box_index = box_index + 1) begin : boxes
            localparam [10:0] LEFT = 128 + 80 * box_index;
            localparam [10:0] RIGHT = 191 + 80 * box_index;
            localparam [3:0] NUMBER = box_index + 1;
            assign box_match[box_index] = row_match &&
                (pixel_x_d2 >= LEFT) && (pixel_x_d2 <= RIGHT);
            assign red_match[box_index] = box_match[box_index] && (code_pix >= NUMBER);
        end
    endgenerate

    // Cero: ocho casillas grises confirman que este FS diagnostico esta cargado.
    // N: las primeras N rojas y el resto grises. Fuera de ellas pasa RGB directo.
    assign out_rgb = !video_de ? 24'h000000 :
                     (|box_match ? (|red_match ? 24'hff0000 : 24'h202020) : in_rgb);
endmodule
