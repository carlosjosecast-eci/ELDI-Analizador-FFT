# Analizador FFT en una Tang Nano 20K

**Carlos Jose Castiblanco y Jarid Camilo Ojeda**  
Proyecto final de Electrónica Digital · Escuela Colombiana de Ingeniería Julio Garavito

Usamos el AD7606 para tomar muestras de AIN1 a 200 kS/s. La Tang reúne 256 muestras por bloque, calcula la FFT y muestra la señal o su espectro por HDMI. Con **S2** cambiamos de vista y con **S1** reiniciamos el analizador.

[Informe en PDF](Informe/informe_eldi_fft.pdf) · [Código HDL](Gowin/src/) · [Proyecto Gowin](Gowin/tang20k_presentacion_eldi_fd73.gprj) · [Bitstream](Programar/ELDI_Analizador_FFT.fs)

## Probarlo en la placa

Conecta el generador a AIN1 y el monitor al HDMI de la Tang. El módulo AD7606 recibe 5 V del pin de la Tang, con tierra común entre la Tang, el ADC y el generador. Usamos lógica de 3,3 V, modo paralelo por bytes con el MSB primero, rango de ±5 V y sobremuestreo desactivado.

<details>
<summary>Cableado y ajustes del ADC</summary>

| Señal del ADC | Pin de la FPGA |
|---|---|
| D0, D1, D2, D3, D4 | 27, 28, 29, 30, 31 |
| D5, D6, D7 | 77, 41, 42 |
| BUSY, FRSTDATA | 48, 73 |
| CONVST, RD, CS, RST | 15, 16, 17, 18 |

Los números corresponden a los pines del encapsulado de la FPGA y aparecen en el archivo de asignaciones de Gowin. En cada fila, los pines siguen el mismo orden de las señales. D15 y D14 van en alto, RANGE en bajo y OS2:OS0 quedan en `000`. CA y CB están unidos en el módulo.

</details>

Carga [ELDI_Analizador_FFT.fs](Programar/ELDI_Analizador_FFT.fs) en SRAM. Para la prueba usa un seno de **3125 Hz**, **2 Vpp** y **0 V** de offset, con el generador en **High Z**. Deben verse cuatro períodos y, al pulsar S2, un pico en el **bin 4**. Para recompilar están el [proyecto de Gowin](Gowin/tang20k_presentacion_eldi_fd73.gprj), sus [restricciones](Gowin/constraints/) y el [script de compilación](Gowin/build.tcl).

## Simular en EDA Playground

Pega [Design.txt](Simulacion/Design.txt) en **Design** y [Testbench.txt](Simulacion/Testbench.txt) en **Testbench**. Usa **SystemVerilog** con **Icarus Verilog** y las opciones `-g2012 -s tb_entrega`.

Los bancos comparan la salida contra valores esperados durante la simulación. Si detectan una diferencia, el mensaje de error indica qué comprobación falló. Si todas pasan, la consola muestra `PASS`. Por defecto se ejecutan el lector del ADC y el encabezado. Para probar otra parte, agrega el selector de la tabla como opción `-D`. Para la FFT, por ejemplo, agrega `-DELDI_TB_FFT`.

| Banco | Qué comprueba | Selector |
|---|---|---|
| [Lector ADC](Simulacion/Bancos/tb_adc_final.sv) | Orden de los bytes, período de muestreo y recuperación ante fallos. | Por defecto |
| [Captura](Simulacion/Bancos/tb_sample_capture.sv) | Orden de las muestras y alternancia de los bancos. | `ELDI_TB_CAPTURA` |
| [Coeficientes FFT](Simulacion/Bancos/tb_fft_twiddle_rom.sv) | Valores y salida registrada de la ROM. | `ELDI_TB_TWIDDLE` |
| [Mariposa](Simulacion/Bancos/tb_fft_butterfly.sv) | Aritmética, redondeo y casos límite. | `ELDI_TB_MARIPOSA` |
| [FFT de 256 puntos](Simulacion/Bancos/tb_fft256_core.sv) | Valores y orden de los bins frente a una DFT de referencia. | `ELDI_TB_FFT` |
| [Magnitud](Simulacion/Bancos/tb_fft_magnitude.sv) | Magnitud calculada y tiempo de respuesta. | `ELDI_TB_MAGNITUD` |
| [Procesador](Simulacion/Bancos/tb_signal_processor.sv) | Publicación de 256 muestras y 129 magnitudes por bloque. | `ELDI_TB_PROCESADOR` |
| [Búfer de pantalla](Simulacion/Bancos/tb_display_buffer.sv) | Lectura y cambio de banco al inicio del cuadro. | `ELDI_TB_BUFFER` |
| [Selector S2](Simulacion/Bancos/tb_view_selector.sv) | Una conmutación por pulsación, incluso si el botón rebota. | `ELDI_TB_SELECTOR` |
| [Barrido](Simulacion/Bancos/tb_video_timing_720p.sv) | Área activa, sincronismos y duración del cuadro 720p. | `ELDI_TB_VIDEO` |
| [Gráficas](Simulacion/Bancos/tb_plot_renderer.sv) | Píxeles de la señal, el espectro y la cuadrícula. | `ELDI_TB_TRAZADOR` |
| [Encabezado](Simulacion/Bancos/tb_presentation_overlay.sv) | Texto, logo, casillas de diagnóstico y alineación con el vídeo. | Por defecto |
| [TMDS](Simulacion/Bancos/tb_tmds_encoder.sv) | Símbolos de datos y control. | `ELDI_TB_TMDS` |
| [Integración](Simulacion/Bancos/tb_integracion_final.sv) | Recorrido desde el ADC simulado hasta el pico del bin 4 y el cambio de vista con S2. | `ELDI_TB_INTEGRACION` |

La simulación verifica la salida hasta los símbolos TMDS. La PLL y los serializadores se incluyen en el proyecto para la FPGA.
