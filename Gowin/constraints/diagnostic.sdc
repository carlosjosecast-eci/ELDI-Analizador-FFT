# Clocks relacionados: 27 MHz -> PLL 371,25 MHz -> pixel 74,25 MHz.
create_clock -name clk27 -period 37.037037 [get_ports {clk27}]
create_generated_clock -name serial_clk -source [get_ports {clk27}] -multiply_by 55 -divide_by 4 [get_pins {u_pll/CLKOUT}]
create_generated_clock -name pix_clk -source [get_pins {u_pll/CLKOUT}] -divide_by 5 [get_pins {u_clkdiv/CLKOUT}]

set_false_path -from [get_ports {key_s1}]
set_false_path -from [get_ports {key_s2}]
set_false_path -from [get_ports {adc_busy}]

# El primer FF de cada toggle recibe una transicion asincrona. La ruta desde
# ese primer FF al segundo sigue temporizada: no se excluyen dominios enteros.
set_false_path -to [get_pins {core/acquisition_video.display/request_meta_s0/D}]
set_false_path -to [get_pins {core/acquisition_video.display/ack_meta_s0/D}]

# Metadato estable desde commit hasta ACK. E1=request_meta, E2=request_sync,
# E3=front_bank: hay dos periodos de PIXEL adicionales antes de capturarlo.
# -end explicito tanto en setup como hold; no modifica otros cruces CDC.
set_multicycle_path -from [get_pins {core/acquisition_video.display/published_bank_s0/Q}] -to [get_pins {core/acquisition_video.display/front_bank_s0/D}] -setup -end 3
set_multicycle_path -from [get_pins {core/acquisition_video.display/published_bank_s0/Q}] -to [get_pins {core/acquisition_video.display/front_bank_s0/D}] -hold -end 2

# DB/FD se capturan despues de RD bajo dos ciclos (74,074 ns).
# Falta un modelo STA externo de tCO de RD, tACCESS ADC, cable y retorno;
# este SDC no acredita el cierre completo de la interfaz externa del ADC.

# Diagnostico aislado: first_valid inicia una transferencia unica. Solo el
# primer FF recibe el cruce; valid_meta->valid_sync permanece temporizado.
set_false_path -to [get_pins {core/diag_overlay/valid_meta_s0/D}]

# code_hold queda estable hasta reset comun. E1=valid_meta, E2=valid_sync,
# E3 o posterior=code_pix en frame_start. Preservar el ajuste de hold con -end.
set_multicycle_path -from [get_pins {core/diag_overlay/code_hold_*_s0/Q}] -to [get_pins {core/diag_overlay/code_pix_*_s0/D}] -setup -end 3
set_multicycle_path -from [get_pins {core/diag_overlay/code_hold_*_s0/Q}] -to [get_pins {core/diag_overlay/code_pix_*_s0/D}] -hold -end 2
