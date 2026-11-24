`timescale 1ns/1ps

// Selector de vista: S2 activo alto, antirrebote y cambio en inicio de cuadro.
// Todos los registros pertenecen al dominio clk (74,25 MHz en el sistema).
module view_selector #(
    parameter integer DEBOUNCE_CYCLES = 1_485_000
) (
    input  wire clk,
    input  wire rst_n,
    input  wire key_s2,
    input  wire frame_start,
    output reg  mode_fft
);

    // Contrato del parametro: DEBOUNCE_CYCLES >= 1.
    localparam integer COUNT_WIDTH =
        (DEBOUNCE_CYCLES > 1) ? $clog2(DEBOUNCE_CYCLES) : 1;
    localparam [COUNT_WIDTH-1:0] LAST_COUNT = DEBOUNCE_CYCLES - 1;

    // Los dos primeros FF reducen la probabilidad de propagar metastabilidad.
    // El filtro solo usa key_sync; no toma decisiones con key_meta.
    reg key_meta;
    reg key_sync;
    reg key_stable;
    reg [COUNT_WIDTH-1:0] opposite_count;
    reg pending_mode;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_meta       <= 1'b0;
            key_sync       <= 1'b0;
            key_stable     <= 1'b0;
            opposite_count <= {COUNT_WIDTH{1'b0}};
            pending_mode   <= 1'b0;
            mode_fft       <= 1'b0;
        end else begin
            key_meta <= key_s2;
            key_sync <= key_meta;

            // Solo N muestras consecutivas opuestas al estado estable lo cambian.
            // Volver al valor estable anula la cuenta parcial de rebotes.
            if (key_sync == key_stable) begin
                opposite_count <= {COUNT_WIDTH{1'b0}};
            end else if (opposite_count == LAST_COUNT) begin
                opposite_count <= {COUNT_WIDTH{1'b0}};
                key_stable <= key_sync;
                // Unicamente el flanco estable 0->1 cambia la vista pendiente.
                // Una pulsacion mantenida no vuelve a alternar.
                if (key_sync)
                    pending_mode <= ~pending_mode;
            end else begin
                opposite_count <= opposite_count + 1'b1;
            end

            // Las asignaciones no bloqueantes usan el pending_mode anterior.
            // Una pulsacion validada justo en frame_start se ve en el siguiente
            // frame_start. No se pierde; varias pulsaciones conservan su paridad.
            if (frame_start)
                mode_fft <= pending_mode;
        end
    end

endmodule
