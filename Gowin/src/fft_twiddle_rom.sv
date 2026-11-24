`timescale 1ns/1ps

// Generado por scripts/generate_twiddles.py. FFT256, W=cos-j*sin.
// 18 bits con signo y 16 bits fraccionales; lectura sincrona habilitada.
// Sin reset de la ROM: su salida es valida despues de un acceso en=1.
module fft_twiddle_rom (
    input  logic               clk,
    input  logic               en,
    input  logic [6:0]         addr,
    output logic signed [17:0] w_re,
    output logic signed [17:0] w_im
);
    always_ff @(posedge clk) begin
        if (en) begin
            case (addr)
                7'd0: begin w_re <= 18'sd65536; w_im <= 18'sd0; end
                7'd1: begin w_re <= 18'sd65516; w_im <= -18'sd1608; end
                7'd2: begin w_re <= 18'sd65457; w_im <= -18'sd3216; end
                7'd3: begin w_re <= 18'sd65358; w_im <= -18'sd4821; end
                7'd4: begin w_re <= 18'sd65220; w_im <= -18'sd6424; end
                7'd5: begin w_re <= 18'sd65043; w_im <= -18'sd8022; end
                7'd6: begin w_re <= 18'sd64827; w_im <= -18'sd9616; end
                7'd7: begin w_re <= 18'sd64571; w_im <= -18'sd11204; end
                7'd8: begin w_re <= 18'sd64277; w_im <= -18'sd12785; end
                7'd9: begin w_re <= 18'sd63944; w_im <= -18'sd14359; end
                7'd10: begin w_re <= 18'sd63572; w_im <= -18'sd15924; end
                7'd11: begin w_re <= 18'sd63162; w_im <= -18'sd17479; end
                7'd12: begin w_re <= 18'sd62714; w_im <= -18'sd19024; end
                7'd13: begin w_re <= 18'sd62228; w_im <= -18'sd20557; end
                7'd14: begin w_re <= 18'sd61705; w_im <= -18'sd22078; end
                7'd15: begin w_re <= 18'sd61145; w_im <= -18'sd23586; end
                7'd16: begin w_re <= 18'sd60547; w_im <= -18'sd25080; end
                7'd17: begin w_re <= 18'sd59914; w_im <= -18'sd26558; end
                7'd18: begin w_re <= 18'sd59244; w_im <= -18'sd28020; end
                7'd19: begin w_re <= 18'sd58538; w_im <= -18'sd29466; end
                7'd20: begin w_re <= 18'sd57798; w_im <= -18'sd30893; end
                7'd21: begin w_re <= 18'sd57022; w_im <= -18'sd32303; end
                7'd22: begin w_re <= 18'sd56212; w_im <= -18'sd33692; end
                7'd23: begin w_re <= 18'sd55368; w_im <= -18'sd35062; end
                7'd24: begin w_re <= 18'sd54491; w_im <= -18'sd36410; end
                7'd25: begin w_re <= 18'sd53581; w_im <= -18'sd37736; end
                7'd26: begin w_re <= 18'sd52639; w_im <= -18'sd39040; end
                7'd27: begin w_re <= 18'sd51665; w_im <= -18'sd40320; end
                7'd28: begin w_re <= 18'sd50660; w_im <= -18'sd41576; end
                7'd29: begin w_re <= 18'sd49624; w_im <= -18'sd42806; end
                7'd30: begin w_re <= 18'sd48559; w_im <= -18'sd44011; end
                7'd31: begin w_re <= 18'sd47464; w_im <= -18'sd45190; end
                7'd32: begin w_re <= 18'sd46341; w_im <= -18'sd46341; end
                7'd33: begin w_re <= 18'sd45190; w_im <= -18'sd47464; end
                7'd34: begin w_re <= 18'sd44011; w_im <= -18'sd48559; end
                7'd35: begin w_re <= 18'sd42806; w_im <= -18'sd49624; end
                7'd36: begin w_re <= 18'sd41576; w_im <= -18'sd50660; end
                7'd37: begin w_re <= 18'sd40320; w_im <= -18'sd51665; end
                7'd38: begin w_re <= 18'sd39040; w_im <= -18'sd52639; end
                7'd39: begin w_re <= 18'sd37736; w_im <= -18'sd53581; end
                7'd40: begin w_re <= 18'sd36410; w_im <= -18'sd54491; end
                7'd41: begin w_re <= 18'sd35062; w_im <= -18'sd55368; end
                7'd42: begin w_re <= 18'sd33692; w_im <= -18'sd56212; end
                7'd43: begin w_re <= 18'sd32303; w_im <= -18'sd57022; end
                7'd44: begin w_re <= 18'sd30893; w_im <= -18'sd57798; end
                7'd45: begin w_re <= 18'sd29466; w_im <= -18'sd58538; end
                7'd46: begin w_re <= 18'sd28020; w_im <= -18'sd59244; end
                7'd47: begin w_re <= 18'sd26558; w_im <= -18'sd59914; end
                7'd48: begin w_re <= 18'sd25080; w_im <= -18'sd60547; end
                7'd49: begin w_re <= 18'sd23586; w_im <= -18'sd61145; end
                7'd50: begin w_re <= 18'sd22078; w_im <= -18'sd61705; end
                7'd51: begin w_re <= 18'sd20557; w_im <= -18'sd62228; end
                7'd52: begin w_re <= 18'sd19024; w_im <= -18'sd62714; end
                7'd53: begin w_re <= 18'sd17479; w_im <= -18'sd63162; end
                7'd54: begin w_re <= 18'sd15924; w_im <= -18'sd63572; end
                7'd55: begin w_re <= 18'sd14359; w_im <= -18'sd63944; end
                7'd56: begin w_re <= 18'sd12785; w_im <= -18'sd64277; end
                7'd57: begin w_re <= 18'sd11204; w_im <= -18'sd64571; end
                7'd58: begin w_re <= 18'sd9616; w_im <= -18'sd64827; end
                7'd59: begin w_re <= 18'sd8022; w_im <= -18'sd65043; end
                7'd60: begin w_re <= 18'sd6424; w_im <= -18'sd65220; end
                7'd61: begin w_re <= 18'sd4821; w_im <= -18'sd65358; end
                7'd62: begin w_re <= 18'sd3216; w_im <= -18'sd65457; end
                7'd63: begin w_re <= 18'sd1608; w_im <= -18'sd65516; end
                7'd64: begin w_re <= 18'sd0; w_im <= -18'sd65536; end
                7'd65: begin w_re <= -18'sd1608; w_im <= -18'sd65516; end
                7'd66: begin w_re <= -18'sd3216; w_im <= -18'sd65457; end
                7'd67: begin w_re <= -18'sd4821; w_im <= -18'sd65358; end
                7'd68: begin w_re <= -18'sd6424; w_im <= -18'sd65220; end
                7'd69: begin w_re <= -18'sd8022; w_im <= -18'sd65043; end
                7'd70: begin w_re <= -18'sd9616; w_im <= -18'sd64827; end
                7'd71: begin w_re <= -18'sd11204; w_im <= -18'sd64571; end
                7'd72: begin w_re <= -18'sd12785; w_im <= -18'sd64277; end
                7'd73: begin w_re <= -18'sd14359; w_im <= -18'sd63944; end
                7'd74: begin w_re <= -18'sd15924; w_im <= -18'sd63572; end
                7'd75: begin w_re <= -18'sd17479; w_im <= -18'sd63162; end
                7'd76: begin w_re <= -18'sd19024; w_im <= -18'sd62714; end
                7'd77: begin w_re <= -18'sd20557; w_im <= -18'sd62228; end
                7'd78: begin w_re <= -18'sd22078; w_im <= -18'sd61705; end
                7'd79: begin w_re <= -18'sd23586; w_im <= -18'sd61145; end
                7'd80: begin w_re <= -18'sd25080; w_im <= -18'sd60547; end
                7'd81: begin w_re <= -18'sd26558; w_im <= -18'sd59914; end
                7'd82: begin w_re <= -18'sd28020; w_im <= -18'sd59244; end
                7'd83: begin w_re <= -18'sd29466; w_im <= -18'sd58538; end
                7'd84: begin w_re <= -18'sd30893; w_im <= -18'sd57798; end
                7'd85: begin w_re <= -18'sd32303; w_im <= -18'sd57022; end
                7'd86: begin w_re <= -18'sd33692; w_im <= -18'sd56212; end
                7'd87: begin w_re <= -18'sd35062; w_im <= -18'sd55368; end
                7'd88: begin w_re <= -18'sd36410; w_im <= -18'sd54491; end
                7'd89: begin w_re <= -18'sd37736; w_im <= -18'sd53581; end
                7'd90: begin w_re <= -18'sd39040; w_im <= -18'sd52639; end
                7'd91: begin w_re <= -18'sd40320; w_im <= -18'sd51665; end
                7'd92: begin w_re <= -18'sd41576; w_im <= -18'sd50660; end
                7'd93: begin w_re <= -18'sd42806; w_im <= -18'sd49624; end
                7'd94: begin w_re <= -18'sd44011; w_im <= -18'sd48559; end
                7'd95: begin w_re <= -18'sd45190; w_im <= -18'sd47464; end
                7'd96: begin w_re <= -18'sd46341; w_im <= -18'sd46341; end
                7'd97: begin w_re <= -18'sd47464; w_im <= -18'sd45190; end
                7'd98: begin w_re <= -18'sd48559; w_im <= -18'sd44011; end
                7'd99: begin w_re <= -18'sd49624; w_im <= -18'sd42806; end
                7'd100: begin w_re <= -18'sd50660; w_im <= -18'sd41576; end
                7'd101: begin w_re <= -18'sd51665; w_im <= -18'sd40320; end
                7'd102: begin w_re <= -18'sd52639; w_im <= -18'sd39040; end
                7'd103: begin w_re <= -18'sd53581; w_im <= -18'sd37736; end
                7'd104: begin w_re <= -18'sd54491; w_im <= -18'sd36410; end
                7'd105: begin w_re <= -18'sd55368; w_im <= -18'sd35062; end
                7'd106: begin w_re <= -18'sd56212; w_im <= -18'sd33692; end
                7'd107: begin w_re <= -18'sd57022; w_im <= -18'sd32303; end
                7'd108: begin w_re <= -18'sd57798; w_im <= -18'sd30893; end
                7'd109: begin w_re <= -18'sd58538; w_im <= -18'sd29466; end
                7'd110: begin w_re <= -18'sd59244; w_im <= -18'sd28020; end
                7'd111: begin w_re <= -18'sd59914; w_im <= -18'sd26558; end
                7'd112: begin w_re <= -18'sd60547; w_im <= -18'sd25080; end
                7'd113: begin w_re <= -18'sd61145; w_im <= -18'sd23586; end
                7'd114: begin w_re <= -18'sd61705; w_im <= -18'sd22078; end
                7'd115: begin w_re <= -18'sd62228; w_im <= -18'sd20557; end
                7'd116: begin w_re <= -18'sd62714; w_im <= -18'sd19024; end
                7'd117: begin w_re <= -18'sd63162; w_im <= -18'sd17479; end
                7'd118: begin w_re <= -18'sd63572; w_im <= -18'sd15924; end
                7'd119: begin w_re <= -18'sd63944; w_im <= -18'sd14359; end
                7'd120: begin w_re <= -18'sd64277; w_im <= -18'sd12785; end
                7'd121: begin w_re <= -18'sd64571; w_im <= -18'sd11204; end
                7'd122: begin w_re <= -18'sd64827; w_im <= -18'sd9616; end
                7'd123: begin w_re <= -18'sd65043; w_im <= -18'sd8022; end
                7'd124: begin w_re <= -18'sd65220; w_im <= -18'sd6424; end
                7'd125: begin w_re <= -18'sd65358; w_im <= -18'sd4821; end
                7'd126: begin w_re <= -18'sd65457; w_im <= -18'sd3216; end
                7'd127: begin w_re <= -18'sd65516; w_im <= -18'sd1608; end
            endcase
        end
    end
endmodule
