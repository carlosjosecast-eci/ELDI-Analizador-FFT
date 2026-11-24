# Compilación de la entrega definitiva. Genera un proyecto en build.
set root_dir [file normalize [file join [file dirname [info script]]]]
set run_id [clock format [clock seconds] -format "eldi_%Y%m%d_%H%M%S"]
set project_name tang20k_presentacion_eldi_fd73
set build_dir [file join $root_dir build $run_id]
file mkdir $build_dir
create_project -name $project_name -dir $build_dir -pn GW2AR-LV18QN88C8/I7 -device_version C -force
set_option -top_module tang20k_top
set_option -verilog_std sysv2017
set_option -global_freq 74.25
set_option -use_mode_as_gpio 1
set_option -gen_text_timing_rpt 1
set_option -cst_warn_to_error 1

add_file [file join $root_dir src analyzer_core.sv]
add_file [file join $root_dir src presentation_font.v]
add_file [file join $root_dir src presentation_logo.v]
add_file [file join $root_dir src presentation_overlay.sv]
add_file [file join $root_dir src display_buffer.sv]
add_file [file join $root_dir src fft256_core.sv]
add_file [file join $root_dir src fft_butterfly.sv]
add_file [file join $root_dir src fft_magnitude.sv]
add_file [file join $root_dir src fft_twiddle_rom.sv]
add_file [file join $root_dir src plot_renderer.sv]
add_file [file join $root_dir src sample_capture.sv]
add_file [file join $root_dir src signal_processor.sv]
add_file [file join $root_dir src tang20k_top.sv]
add_file [file join $root_dir src tmds_encoder.sv]
add_file [file join $root_dir src video_timing_720p.sv]
add_file [file join $root_dir src view_selector.sv]
add_file [file join $root_dir src ad7606_byte_reader_v1_after_busy.sv]
add_file [file join $root_dir src diagnostic_overlay.sv]
add_file [file join $root_dir constraints tang20k_fd73_propuesto.cst]
add_file [file join $root_dir constraints diagnostic.sdc]

set build_started [clock seconds]
puts "ELDI PRESENTATION BUILD: proyecto=$project_name; carpeta=$build_dir"
run all
set project_dir [file join $build_dir $project_name]
set bitstream [file join $project_dir impl pnr ${project_name}.fs]
if {![file exists $bitstream] || [file mtime $bitstream] < $build_started} {
    error "No se genero un FS diagnostico nuevo; revisar los reportes de Gowin"
}
puts "ELDI PRESENTATION RESULT: bitstream=$bitstream"
puts "ELDI PRESENTATION REPORTS: [file join $project_dir impl pnr]"
run close
exit
