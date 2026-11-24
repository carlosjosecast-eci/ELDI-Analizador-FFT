`timescale 1ns/1ps

// Dos bancos de visualizacion y transferencia CDC por request/ack toggle.
// Los datos publicados permanecen estables hasta recibir el ACK sincronizado.
// Ambos resets se deben activar juntos; su liberacion se sincroniza por dominio.
module display_buffer (
    input  wire               wr_clk,
    input  wire               wr_rst_n,
    input  wire               pix_clk,
    input  wire               pix_rst_n,
    input  wire               frame_start,

    input  wire               frame_begin,
    input  wire [31:0]        frame_seq,
    input  wire               wave_valid,
    input  wire [7:0]         wave_index,
    input  wire signed [15:0] wave_sample,
    input  wire               spectrum_valid,
    input  wire [7:0]         spectrum_index,
    input  wire [17:0]        spectrum_mag,
    input  wire               frame_done,
    output wire               wr_busy,
    output reg                wr_fault_latched,

    output reg                front_valid,
    output reg [31:0]         front_seq,
    input  wire               rd_en,
    input  wire [7:0]         rd_wave_addr,
    input  wire [7:0]         rd_spectrum_addr,
    output reg                rd_valid,
    output wire signed [15:0] rd_wave_prev,
    output wire signed [15:0] rd_wave_sample,
    output wire [17:0]        rd_spectrum_mag
);

    reg active;
    reg waiting_ack;
    reg back_bank;
    reg [31:0] working_seq;
    reg [8:0] wave_count;
    reg [7:0] spectrum_count;
    reg signed [15:0] previous_sample;

    reg request_toggle;
    reg published_bank;
    reg [31:0] published_seq;
    reg ack_toggle;
    reg ack_meta, ack_sync;
    reg request_meta, request_sync;
    reg front_bank;

    wire accept_begin = frame_begin && !active && !waiting_ack && !wr_fault_latched;
    wire accepted_frame = active || accept_begin;
    reg [8:0] next_wave_count;
    reg [7:0] next_spectrum_count;
    reg malformed_frame;
    reg commit_frame;
    reg wave_write;
    reg spectrum_write;
    reg [31:0] wave_write_data;

    // Indisponible si se esta recibiendo, esperando intercambio o en fallo.
    assign wr_busy = active || waiting_ack || wr_fault_latched;

    // Solo se comprueban los cuadros aceptados. Si frame_begin llega mientras
    // waiting_ack=1, se ignoran ese cuadro y sus eventos sin active: no frenamos
    // el procesador. Que ACK llegue a mitad de ese cuadro no lo acepta a medias.
    always_comb begin
        next_wave_count = accept_begin ? 9'd0 : wave_count;
        next_spectrum_count = accept_begin ? 8'd0 : spectrum_count;
        malformed_frame = 1'b0;
        commit_frame = 1'b0;
        wave_write = 1'b0;
        spectrum_write = 1'b0;
        wave_write_data = '0;

        if (wr_rst_n && !wr_fault_latched && !waiting_ack) begin
            if (active && frame_begin) begin
                malformed_frame = 1'b1;
            end else if (accepted_frame) begin
                if (wave_valid) begin
                    if ((next_wave_count >= 9'd256) ||
                        (wave_index != next_wave_count[7:0])) begin
                        malformed_frame = 1'b1;
                    end else begin
                        wave_write = 1'b1;
                        // Indice cero se une consigo mismo, no con otro cuadro.
                        wave_write_data = {
                            (next_wave_count == 9'd0) ? wave_sample : previous_sample,
                            wave_sample
                        };
                        next_wave_count = next_wave_count + 9'd1;
                    end
                end

                // Se usa el contador ya actualizado: permite ultimo wave y
                // primer bin en el mismo flanco, sin aceptar espectro prematuro.
                if (spectrum_valid) begin
                    if ((next_wave_count != 9'd256) ||
                        (next_spectrum_count >= 8'd129) ||
                        (spectrum_index != next_spectrum_count)) begin
                        malformed_frame = 1'b1;
                    end else begin
                        spectrum_write = 1'b1;
                        next_spectrum_count = next_spectrum_count + 8'd1;
                    end
                end

                if (frame_done) begin
                    // Incluye bin128 que puede llegar junto a frame_done.
                    if ((next_wave_count != 9'd256) ||
                        (next_spectrum_count != 8'd129))
                        malformed_frame = 1'b1;
                    else
                        commit_frame = 1'b1;
                end
            end
        end

        // Un flanco mal formado no escribe nada ni publica un request.
        if (malformed_frame) begin
            wave_write = 1'b0;
            spectrum_write = 1'b0;
            commit_frame = 1'b0;
        end
    end

    // Sincronizador del ACK hacia el escritor. No se sincronizan por separado
    // los bits de published_seq: son un bus estable asociado al request.
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            ack_meta <= 1'b0;
            ack_sync <= 1'b0;
        end else begin
            ack_meta <= ack_toggle;
            ack_sync <= ack_meta;
        end
    end

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            active <= 1'b0;
            waiting_ack <= 1'b0;
            back_bank <= 1'b1;
            working_seq <= 32'd0;
            wave_count <= 9'd0;
            spectrum_count <= 8'd0;
            previous_sample <= 16'sd0;
            request_toggle <= 1'b0;
            published_bank <= 1'b1;
            published_seq <= 32'd0;
            wr_fault_latched <= 1'b0;
        end else begin
            if (waiting_ack && (ack_sync == request_toggle)) begin
                waiting_ack <= 1'b0;
                back_bank <= ~published_bank;
            end

            // Se usa waiting_ack ANTES del flanco: un frame_begin simultaneo
            // con la observacion de ACK se puede descartar deliberadamente.
            if (!wr_fault_latched && !waiting_ack) begin
                if (malformed_frame) begin
                    active <= 1'b0;
                    wr_fault_latched <= 1'b1;
                end else if (accepted_frame) begin
                    if (accept_begin)
                        working_seq <= frame_seq;
                    active <= !commit_frame;
                    wave_count <= next_wave_count;
                    spectrum_count <= next_spectrum_count;
                    if (wave_write)
                        previous_sample <= wave_sample;
                    if (commit_frame) begin
                        published_bank <= back_bank;
                        published_seq <= accept_begin ? frame_seq : working_seq;
                        request_toggle <= ~request_toggle;
                        waiting_ack <= 1'b1;
                    end
                end
            end
        end
    end

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            request_meta <= 1'b0;
            request_sync <= 1'b0;
        end else begin
            request_meta <= request_toggle;
            request_sync <= request_meta;
        end
    end

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            front_bank <= 1'b0;
            front_valid <= 1'b0;
            front_seq <= 32'd0;
            ack_toggle <= 1'b0;
        end else if (frame_start && (request_sync != ack_toggle)) begin
            // Metadatos estables desde commit hasta el ACK de vuelta.
            front_bank <= published_bank;
            front_seq <= published_seq;
            front_valid <= 1'b1;
            ack_toggle <= request_sync;
        end
    end

    // Cuatro memorias de doble reloj y un puerto de escritura/lectura cada una.
    // No se reinician arrays ni registros de salida para permitir BSRAM.
    reg [31:0] wave_bank0 [0:255];
    reg [31:0] wave_bank1 [0:255];
    reg [17:0] spectrum_bank0 [0:255];
    reg [17:0] spectrum_bank1 [0:255];
    reg [31:0] wave_q0, wave_q1;
    reg [17:0] spectrum_q0, spectrum_q1;
    wire read_accept = pix_rst_n && rd_en && front_valid;
    wire spectrum_in_range = rd_spectrum_addr <= 8'd128;
    wire [7:0] spectrum_read_addr = spectrum_in_range ? rd_spectrum_addr : 8'd0;
    reg read_bank_q;
    reg spectrum_in_range_q;

    always @(posedge wr_clk) begin
        if (wave_write && !back_bank)
            wave_bank0[wave_index] <= wave_write_data;
        if (spectrum_write && !back_bank)
            spectrum_bank0[spectrum_index] <= spectrum_mag;
    end
    always @(posedge wr_clk) begin
        if (wave_write && back_bank)
            wave_bank1[wave_index] <= wave_write_data;
        if (spectrum_write && back_bank)
            spectrum_bank1[spectrum_index] <= spectrum_mag;
    end

    always @(posedge pix_clk) begin
        if (read_accept && !front_bank) begin
            wave_q0 <= wave_bank0[rd_wave_addr];
            spectrum_q0 <= spectrum_bank0[spectrum_read_addr];
        end
    end
    always @(posedge pix_clk) begin
        if (read_accept && front_bank) begin
            wave_q1 <= wave_bank1[rd_wave_addr];
            spectrum_q1 <= spectrum_bank1[spectrum_read_addr];
        end
    end

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            rd_valid <= 1'b0;
            read_bank_q <= 1'b0;
            spectrum_in_range_q <= 1'b0;
        end else begin
            rd_valid <= read_accept;
            if (read_accept) begin
                // Capturar el banco anterior al flanco tambien si hay swap.
                read_bank_q <= front_bank;
                spectrum_in_range_q <= spectrum_in_range;
            end
        end
    end

    wire [31:0] selected_wave = read_bank_q ? wave_q1 : wave_q0;
    assign rd_wave_prev = $signed(selected_wave[31:16]);
    assign rd_wave_sample = $signed(selected_wave[15:0]);
    assign rd_spectrum_mag = !spectrum_in_range_q ? 18'd0 :
                             (read_bank_q ? spectrum_q1 : spectrum_q0);
endmodule
