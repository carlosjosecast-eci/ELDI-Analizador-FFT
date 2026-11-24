`timescale 1ns/1ps

// Captura continua de bloques de 256 muestras signed de 16 bits a 27 MHz.
// El ADC no recibe contrapresion: un consumidor atrasado provoca fallo retenido.
module sample_capture (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               sample_valid,
    input  wire signed [15:0] sample_signed,

    output reg                block_valid,
    output reg                block_bank,
    output reg [31:0]         block_seq,
    input  wire               block_release,
    output reg                overrun_latched,

    input  wire               rd_en,
    input  wire               rd_bank,
    input  wire [7:0]         rd_addr,
    output wire signed [15:0] rd_sample,
    output reg                rd_valid
);

    // Dos memorias independientes: un puerto de escritura y otro de lectura.
    // No se reinician ni el contenido ni sus registros de lectura para permitir
    // inferencia de BSRAM. rd_sample solo es significativo si rd_valid es alto.
    reg signed [15:0] bank0 [0:255];
    reg signed [15:0] bank1 [0:255];
    reg signed [15:0] bank0_read;
    reg signed [15:0] bank1_read;

    reg write_bank;
    reg [7:0] write_addr;
    reg [31:0] next_seq;
    reg read_bank_q;

    wire write_accept = rst_n && sample_valid && !overrun_latched;
    // En fallo se permite inspeccionar el bloque que sigue publicado.
    // La decision usa la propiedad del banco ANTES del flanco de reloj.
    wire read_accept = rst_n && rd_en && block_valid &&
                       (rd_bank == block_bank);

    always @(posedge clk) begin
        if (write_accept && !write_bank)
            bank0[write_addr] <= sample_signed;
        if (read_accept && !rd_bank)
            bank0_read <= bank0[rd_addr];
    end

    always @(posedge clk) begin
        if (write_accept && write_bank)
            bank1[write_addr] <= sample_signed;
        if (read_accept && rd_bank)
            bank1_read <= bank1[rd_addr];
    end

    assign rd_sample = read_bank_q ? bank1_read : bank0_read;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_bank      <= 1'b0;
            write_addr      <= 8'd0;
            next_seq        <= 32'd0;
            block_valid     <= 1'b0;
            block_bank      <= 1'b0;
            block_seq       <= 32'd0;
            overrun_latched <= 1'b0;
            read_bank_q     <= 1'b0;
            rd_valid        <= 1'b0;
        end else begin
            // Una solicitud valida produce dato y rd_valid tras este flanco.
            // Una solicitud coincidente con release aun puede leer el banco
            // anterior. El consumidor libera despues de recibir el ultimo dato.
            rd_valid <= read_accept;
            if (read_accept)
                read_bank_q <= rd_bank;

            // El fallo se recupera unicamente con reset. Conserva la publicacion
            // pendiente para depuracion e ignora muestras y liberaciones futuras.
            if (!overrun_latched) begin
                if (block_release && block_valid)
                    block_valid <= 1'b0;

                if (sample_valid) begin
                    if (write_addr == 8'd255) begin
                        if (block_valid && !block_release) begin
                            // Se completo el banco libre, pero no se puede volver
                            // al pendiente. No se altera ese bloque ni su metadata.
                            overrun_latched <= 1'b1;
                        end else begin
                            // La muestra 255 se escribe en este mismo flanco.
                            // Las primeras lecturas del bloque se aceptan en el
                            // siguiente: el ultimo dato ya estara almacenado.
                            block_valid <= 1'b1;
                            block_bank <= write_bank;
                            block_seq <= next_seq;
                            next_seq <= next_seq + 32'd1;
                            write_bank <= ~write_bank;
                            write_addr <= 8'd0;
                        end
                    end else begin
                        write_addr <= write_addr + 8'd1;
                    end
                end
            end
        end
    end

endmodule
