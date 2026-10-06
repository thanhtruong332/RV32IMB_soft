set script_dir [file normalize [file dirname [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
create_project RV32IMB_soft [file join $repo_root vivado_project] -part xc7z020clg484-2 -force
set_property target_language Verilog [current_project]
add_files [glob -nocomplain [file join $repo_root rtl *.v]]
add_files -fileset sim_1 [glob -nocomplain [file join $repo_root sim *.v]]
add_files -fileset sim_1 [glob -nocomplain [file join $repo_root firmware images *.mem]]
set_property top rv32i_top [get_filesets sources_1]
set_property top tb_expG_scale_rv32imb_16b_ecb [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "PORTABLE_PROJECT=[get_property DIRECTORY [current_project]]"
puts "SIM_TOP=[get_property TOP [get_filesets sim_1]]"
