`timescale 1ns/1ps

// Variante de diagnóstico para FD en J6-1. Lee solo V1 después de BUSY.
// Se conservan Parallel Byte, HBEN alto (MSB primero) y 135 ciclos por CONVST.
module ad7606_byte_reader #(
    parameter integer STARTUP_CYCLES = 1_350_000
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               adc_busy,
    input  wire               adc_fd,
    input  wire [7:0]         adc_db,
    output reg                adc_convst,
    output reg                adc_cs_n,
    output reg                adc_rd_n,
    output reg                adc_reset,
    output reg signed [15:0]  sample_signed,
    output reg                sample_valid,
    output reg                fault_latched,
    output reg [3:0]          fault_code
);
    localparam integer STARTUP_WIDTH =
        (STARTUP_CYCLES > 1) ? $clog2(STARTUP_CYCLES) : 1;
    localparam [7:0] PERIOD_LAST = 8'd134;
    localparam [7:0] BUSY_RISE_LAST = 8'd7;
    localparam [7:0] BUSY_FALL_LAST = 8'd127;
    localparam [3:0] MSB_RD_LAST = 4'd9; // 10 ciclos bajos, 370 ns.
    localparam [3:0] LSB_RD_LAST = 4'd1; // Dos ciclos bajos, 74 ns.

    typedef enum logic [3:0] {
        WAIT_POWER, HOLD_RESET, RESET_GAP, WAIT_BUSY_RISE, WAIT_BUSY_FALL,
        READ_SETUP, READ_LOW, READ_GAP, READ_COMMIT, CONVERSION_DONE
    } state_t;
    state_t state;

    reg [STARTUP_WIDTH-1:0] startup_count;
    reg [1:0] reset_count;
    reg reset_gap_count;
    reg [7:0] cycle_count;
    reg [3:0] rd_count;
    reg second_byte;
    reg busy_low_seen;
    reg [7:0] msb;
    reg signed [15:0] pending_sample;
    reg busy_meta, busy_sync;
    reg [3:0] pending_fault;

    wire running = (state != WAIT_POWER) && (state != HOLD_RESET) && (state != RESET_GAP);
    wire reading = (state == READ_SETUP) || (state == READ_LOW) ||
                   (state == READ_GAP) || (state == READ_COMMIT);
    wire rd_due = (rd_count == (second_byte ? LSB_RD_LAST : MSB_RD_LAST));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_meta <= 1'b0;
            busy_sync <= 1'b0;
        end else begin
            busy_meta <= adc_busy;
            busy_sync <= busy_meta;
        end
    end

    always_comb begin
        pending_fault = 4'd0;
        if (reading && busy_sync)
            pending_fault = 4'd4; // BUSY reaparece durante lectura.
        else if ((state == WAIT_BUSY_RISE) && !busy_sync && (cycle_count >= BUSY_RISE_LAST))
            pending_fault = 4'd1;
        else if ((state == WAIT_BUSY_FALL) && busy_sync && (cycle_count >= BUSY_FALL_LAST))
            pending_fault = 4'd2;
        else if (running && (cycle_count == PERIOD_LAST) &&
                 ((state != CONVERSION_DONE) || busy_sync))
            pending_fault = 4'd5;
        else if ((state == READ_LOW) && rd_due) begin
            // Cada lectura siguiente a una conversión empieza en V1.
            // Ambos bytes deben estar marcados como V1 antes de publicar.
            case (adc_fd)
                1'b1: begin end
                default: pending_fault = 4'd3;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= WAIT_POWER;
            startup_count <= '0;
            reset_count <= '0;
            reset_gap_count <= 1'b0;
            cycle_count <= '0;
            rd_count <= '0;
            second_byte <= 1'b0;
            busy_low_seen <= 1'b0;
            msb <= '0;
            pending_sample <= '0;
            adc_convst <= 1'b0;
            adc_cs_n <= 1'b1;
            adc_rd_n <= 1'b1;
            adc_reset <= 1'b0;
            sample_signed <= '0;
            sample_valid <= 1'b0;
            fault_latched <= 1'b0;
            fault_code <= 4'd0;
        end else begin
            sample_valid <= 1'b0;
            if (fault_latched || (pending_fault != 4'd0)) begin
                adc_convst <= 1'b0;
                adc_cs_n <= 1'b1;
                adc_rd_n <= 1'b1;
                adc_reset <= 1'b0;
                if (!fault_latched) begin
                    fault_latched <= 1'b1;
                    fault_code <= pending_fault;
                end
            end else if (!running) begin
                case (state)
                    WAIT_POWER: begin
                        if (startup_count == STARTUP_CYCLES - 1) begin
                            reset_count <= 2'd0;
                            adc_reset <= 1'b1;
                            state <= HOLD_RESET;
                        end else startup_count <= startup_count + 1'b1;
                    end
                    HOLD_RESET: begin
                        if (reset_count == 2'd3) begin
                            reset_gap_count <= 1'b0;
                            adc_reset <= 1'b0;
                            state <= RESET_GAP;
                        end else reset_count <= reset_count + 1'b1;
                    end
                    RESET_GAP: begin
                        if (reset_gap_count) begin
                            cycle_count <= 8'd0;
                            adc_convst <= 1'b1;
                            state <= WAIT_BUSY_RISE;
                        end else reset_gap_count <= 1'b1;
                    end
                    default: state <= WAIT_POWER;
                endcase
            end else if (cycle_count == PERIOD_LAST) begin
                // Solo se llega aquí si la muestra anterior se publicó.
                cycle_count <= 8'd0;
                adc_convst <= 1'b1;
                state <= WAIT_BUSY_RISE;
            end else begin
                cycle_count <= cycle_count + 1'b1;
                if (cycle_count == 8'd1) adc_convst <= 1'b0;
                case (state)
                    WAIT_BUSY_RISE: begin
                        if (busy_sync) begin
                            busy_low_seen <= 1'b0;
                            state <= WAIT_BUSY_FALL;
                        end
                    end
                    WAIT_BUSY_FALL: begin
                        if (busy_sync) busy_low_seen <= 1'b0;
                        else if (busy_low_seen) begin
                            second_byte <= 1'b0;
                            adc_cs_n <= 1'b0;
                            state <= READ_SETUP;
                        end else busy_low_seen <= 1'b1;
                    end
                    READ_SETUP, READ_GAP: begin
                        adc_rd_n <= 1'b0;
                        rd_count <= 4'd0;
                        state <= READ_LOW;
                    end
                    READ_LOW: begin
                        if (rd_due) begin
                            adc_rd_n <= 1'b1;
                            if (second_byte) begin
                                pending_sample <= $signed({msb, adc_db});
                                state <= READ_COMMIT;
                            end else begin
                                msb <= adc_db;
                                second_byte <= 1'b1;
                                state <= READ_GAP;
                            end
                        end else rd_count <= rd_count + 1'b1;
                    end
                    READ_COMMIT: begin
                        adc_cs_n <= 1'b1;
                        sample_signed <= pending_sample;
                        sample_valid <= 1'b1;
                        state <= CONVERSION_DONE;
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule
