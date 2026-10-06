if {$argc != 1} {
    error "Usage: vivado -mode batch -source scripts/run_test.tcl -tclargs <MODE_PAYLOAD>"
}
set test_case [lindex $argv 0]
array set test_tops {
    ECB_16B tb_expG_scale_rv32imb_16b_ecb
    ECB_256B tb_expG_scale_rv32imb_256b_ecb
    ECB_4KiB tb_expG_scale_rv32imb_4kib_ecb
    CBC_16B tb_expG_scale_rv32imb_16b_cbc
    CBC_256B tb_expG_scale_rv32imb_256b_cbc
    CBC_4KiB tb_expG_scale_rv32imb_4kib_cbc
    CFB_16B tb_expG_scale_rv32imb_16b_cfb128
    CFB_256B tb_expG_scale_rv32imb_256b_cfb128
    CFB_4KiB tb_expG_scale_rv32imb_4kib_cfb128
    CTR_16B tb_expG_scale_rv32imb_16b_ctr
    CTR_256B tb_expG_scale_rv32imb_256b_ctr
    CTR_4KiB tb_expG_scale_rv32imb_4kib_ctr
}
if {![info exists test_tops($test_case)]} {
    error "Unknown software test case: $test_case"
}
source [file join [file dirname [info script]] create_project.tcl]
set_property top $test_tops($test_case) [get_filesets sim_1]
update_compile_order -fileset sim_1
puts "SOFTWARE_TEST_CASE=$test_case"
puts "SIM_TOP=[get_property TOP [get_filesets sim_1]]"
launch_simulation
run all
close_sim
