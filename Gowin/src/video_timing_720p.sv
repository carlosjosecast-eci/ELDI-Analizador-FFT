`timescale 1ns/1ps

// Barrido 1280x720p60: reloj de pixel nominal 74,25 MHz, total 1650x750.
// El origen (0,0) es el primer pixel activo; los porches vienen despues.
module video_timing_720p (
    input  wire        clk,
    input  wire        rst_n,
    output reg [10:0]  x,
    output reg [9:0]   y,
    output wire        de,
    output wire        hsync,
    output wire        vsync,
    output wire        frame_start
);

    assign de = rst_n && (x < 11'd1280) && (y < 10'd720);
    assign hsync = rst_n && (x >= 11'd1390) && (x < 11'd1430);
    assign vsync = rst_n && (y >= 10'd725) && (y < 10'd730);
    assign frame_start = rst_n && (x == 11'd0) && (y == 10'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x <= 11'd0;
            y <= 10'd0;
        end else if (x == 11'd1649) begin
            x <= 11'd0;
            if (y == 10'd749)
                y <= 10'd0;
            else
                y <= y + 10'd1;
        end else begin
            x <= x + 11'd1;
        end
    end

endmodule
