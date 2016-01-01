# Halt the flow with an error if the timing constraints weren't met
#Taken from http://xillybus.com/tutorials/vivado-timing-constraints-error

set minireport [report_timing_summary -no_header -no_detailed_paths -return_string]

if {! [string match -nocase {*timing constraints are met*} $minireport]} {
    send_msg_id showstopper-0 error "Timing constraints weren't met. Please check your design."
    return -code error
}