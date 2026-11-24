`timescale 1ns/1ps

// Adaptacion fisica exclusiva de Tang Nano 20K GW2AR-18C.
// No se usa en la simulacion portable; las primitivas se verifican con Gowin
// y con las dos pruebas fisicas documentadas en docs/HARDWARE.md.
module tang20k_top #(
    parameter integer VIDEO_TEST_PATTERN = 0
) (
    input wire clk27,
    input wire key_s1,
    input wire key_s2,
    input wire adc_busy,
    input wire adc_fd,
    input wire [7:0] adc_db,
    output wire adc_convst,
    output wire adc_cs_n,
    output wire adc_rd_n,
    output wire adc_reset,
    output wire hdmi_clk_p, hdmi_clk_n,
    output wire hdmi_blue_p, hdmi_blue_n,
    output wire hdmi_green_p, hdmi_green_n,
    output wire hdmi_red_p, hdmi_red_n,
    output wire led_fault_n,
    output wire led_mode_n
);

    wire serial_clk, pix_clk, pll_lock;
    wire raw_reset_n = pll_lock && !key_s1;
    (* syn_preserve = 1 *) reg [3:0] reset27_pipe;
    (* syn_preserve = 1 *) reg [3:0] resetpix_pipe;
    wire rst27_n = reset27_pipe[3];
    wire rstpix_n = resetpix_pipe[3];
    wire [9:0] tmds_red, tmds_green, tmds_blue;
    wire mode_fft, adc_fault, processor_fault, display_fault;
    wire front_valid;
    wire [31:0] front_seq;

    // Parametros del ejemplo HDMI oficial local de Sipeed: 27*55/4=371,25 MHz.
    // S1 reinicia PLL; la ausencia de LOCK mantiene ambos dominios en reset.
    rPLL #(
        .FCLKIN("27"), .DYN_IDIV_SEL("false"), .IDIV_SEL(3),
        .DYN_FBDIV_SEL("false"), .FBDIV_SEL(54),
        .DYN_ODIV_SEL("false"), .ODIV_SEL(2),
        .PSDA_SEL("0000"), .DYN_DA_EN("true"), .DUTYDA_SEL("1000"),
        .CLKOUT_FT_DIR(1'b1), .CLKOUTP_FT_DIR(1'b1),
        .CLKOUT_DLY_STEP(0), .CLKOUTP_DLY_STEP(0),
        .CLKFB_SEL("internal"), .CLKOUT_BYPASS("false"),
        .CLKOUTP_BYPASS("false"), .CLKOUTD_BYPASS("false"),
        .DYN_SDIV_SEL(2), .CLKOUTD_SRC("CLKOUT"),
        .CLKOUTD3_SRC("CLKOUT"), .DEVICE("GW2AR-18C")
    ) u_pll (
        .CLKIN(clk27), .CLKFB(1'b0), .RESET(key_s1), .RESET_P(1'b0),
        .FBDSEL(6'd0), .IDSEL(6'd0), .ODSEL(6'd0),
        .PSDA(4'd0), .DUTYDA(4'd0), .FDLY(4'd0),
        .CLKOUT(serial_clk), .LOCK(pll_lock),
        .CLKOUTP(), .CLKOUTD(), .CLKOUTD3()
    );

    CLKDIV #(.DIV_MODE("5"), .GSREN("false")) u_clkdiv (
        .HCLKIN(serial_clk), .RESETN(raw_reset_n), .CALIB(1'b1),
        .CLKOUT(pix_clk)
    );

    // Asercion comun asincrona; liberacion despues de cuatro flancos propios.
    // No se liberan unilateralmente los extremos del protocolo CDC.
    always @(posedge clk27 or negedge raw_reset_n) begin
        if (!raw_reset_n) reset27_pipe <= 4'b0000;
        else reset27_pipe <= {reset27_pipe[2:0], 1'b1};
    end
    always @(posedge pix_clk or negedge raw_reset_n) begin
        if (!raw_reset_n) resetpix_pipe <= 4'b0000;
        else resetpix_pipe <= {resetpix_pipe[2:0], 1'b1};
    end

    analyzer_core #(
        .ADC_STARTUP_CYCLES(1_350_000),
        .DEBOUNCE_CYCLES(1_485_000),
        .VIDEO_TEST_PATTERN(VIDEO_TEST_PATTERN)
    ) core (
        .clk27(clk27), .pix_clk(pix_clk), .rst27_n(rst27_n), .rstpix_n(rstpix_n),
        .key_s2(key_s2), .adc_busy(adc_busy), .adc_fd(adc_fd), .adc_db(adc_db),
        .adc_convst(adc_convst), .adc_cs_n(adc_cs_n),
        .adc_rd_n(adc_rd_n), .adc_reset(adc_reset),
        .tmds_red(tmds_red), .tmds_green(tmds_green), .tmds_blue(tmds_blue),
        .mode_fft(mode_fft), .adc_fault(adc_fault),
        .processor_fault(processor_fault), .display_fault(display_fault),
        .front_valid(front_valid), .front_seq(front_seq)
    );

    // Los LED de la placa encienden con cero:19=falla,20=vista FFT.
    assign led_fault_n = !(adc_fault || processor_fault || display_fault);
    assign led_mode_n = !mode_fft;

    // OSER10: reset ASINCRONO comun con CLKDIV, segun el ejemplo Sipeed.
    // No se declara aqui cierre STA de su liberacion asincrona. La logica
    // del core sigue retenida por sus resets sincronizados de cuatro etapas.
    tang20k_tmds_lane u_lane_blue (
        .pix_clk(pix_clk), .serial_clk(serial_clk), .reset(!raw_reset_n),
        .word(tmds_blue), .pad_p(hdmi_blue_p), .pad_n(hdmi_blue_n)
    );
    tang20k_tmds_lane u_lane_green (
        .pix_clk(pix_clk), .serial_clk(serial_clk), .reset(!raw_reset_n),
        .word(tmds_green), .pad_p(hdmi_green_p), .pad_n(hdmi_green_n)
    );
    tang20k_tmds_lane u_lane_red (
        .pix_clk(pix_clk), .serial_clk(serial_clk), .reset(!raw_reset_n),
        .word(tmds_red), .pad_p(hdmi_red_p), .pad_n(hdmi_red_n)
    );
    // Mismo camino OSER10 para el reloj reenviado: D0..4=0 y D5..9=1.
    // La palabra se transmite desde bit0, igual que los tres canales de datos.
    tang20k_tmds_lane u_lane_clock (
        .pix_clk(pix_clk), .serial_clk(serial_clk), .reset(!raw_reset_n),
        .word(10'b1111100000), .pad_p(hdmi_clk_p), .pad_n(hdmi_clk_n)
    );
endmodule

`timescale 1ns/1ps
// Una palabra por PCLK, diez bits enviados por las dos aristas de FCLK=5*PCLK.
module tang20k_tmds_lane (
    input wire pix_clk,
    input wire serial_clk,
    input wire reset,
    input wire [9:0] word,
    output wire pad_p,
    output wire pad_n
);
    wire serial_data;
    OSER10 #(.GSREN("false"), .LSREN("true")) u_oser (
        .D0(word[0]), .D1(word[1]), .D2(word[2]), .D3(word[3]), .D4(word[4]),
        .D5(word[5]), .D6(word[6]), .D7(word[7]), .D8(word[8]), .D9(word[9]),
        .PCLK(pix_clk), .FCLK(serial_clk), .RESET(reset), .Q(serial_data)
    );
    TLVDS_OBUF u_obuf (.I(serial_data), .O(pad_p), .OB(pad_n));
endmodule

`timescale 1ns/1ps
// Alias de elaboracion: Gowin CLI no ofrece override de parametro en set_option.
// Conserva los mismos puertos/CST y selecciona el parametro del MISMO diseno.
module tang20k_bars_top (
    input wire clk27, key_s1, key_s2, adc_busy, adc_fd,
    input wire [7:0] adc_db,
    output wire adc_convst, adc_cs_n, adc_rd_n, adc_reset,
    output wire hdmi_clk_p, hdmi_clk_n,
    output wire hdmi_blue_p, hdmi_blue_n,
    output wire hdmi_green_p, hdmi_green_n,
    output wire hdmi_red_p, hdmi_red_n,
    output wire led_fault_n, led_mode_n
);
    tang20k_top #(.VIDEO_TEST_PATTERN(1)) hardware (
        .clk27(clk27), .key_s1(key_s1), .key_s2(key_s2),
        .adc_busy(adc_busy), .adc_fd(adc_fd), .adc_db(adc_db),
        .adc_convst(adc_convst), .adc_cs_n(adc_cs_n), .adc_rd_n(adc_rd_n),
        .adc_reset(adc_reset), .hdmi_clk_p(hdmi_clk_p), .hdmi_clk_n(hdmi_clk_n),
        .hdmi_blue_p(hdmi_blue_p), .hdmi_blue_n(hdmi_blue_n),
        .hdmi_green_p(hdmi_green_p), .hdmi_green_n(hdmi_green_n),
        .hdmi_red_p(hdmi_red_p), .hdmi_red_n(hdmi_red_n),
        .led_fault_n(led_fault_n), .led_mode_n(led_mode_n)
    );
endmodule
