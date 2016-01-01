`timescale 1ns / 1ps

import pcieInterfaces::*;
import hardcoreConfig::*;

//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 27.02.2015 10:45:34
// Design Name: 
// Module Name: hardcore
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module hardcore # (
	parameter int unsigned CHANNELS = 4,
	parameter hardcoreConfig::channelMode_t [0:CHANNELS-1] CHANNEL_MODES = '{default: hardcoreConfig::CM_NOT_PRESENT},
	parameter hardcoreConfig::channelType_t [0:CHANNELS-1] CHANNEL_TYPES = '{default: hardcoreConfig::CT_GENERIC},
	parameter int unsigned INTERFACEWIDTH = pcieInterfaces::INTERFACEWIDTH,
	parameter int unsigned PL_LINK_CAP_MAX_LINK_WIDTH = 8,
	parameter int unsigned CHANNELADDRESSBITS = 3,
	parameter int unsigned ADDRESSBIT_OFFSET = 2,
	parameter int unsigned SEND_CHANNELS = hardcoreConfig::channelInfoParser #(CHANNELS)::channelModeCount(CHANNEL_MODES, hardcoreConfig::CM_READ_ONLY),
	parameter int unsigned RECEIVE_CHANNELS  = hardcoreConfig::channelInfoParser #(CHANNELS)::channelModeCount(CHANNEL_MODES, hardcoreConfig::CM_WRITE_ONLY)
) (
	output [(PL_LINK_CAP_MAX_LINK_WIDTH - 1) : 0] pci_exp_txp,
	output [(PL_LINK_CAP_MAX_LINK_WIDTH - 1) : 0] pci_exp_txn,
	input  [(PL_LINK_CAP_MAX_LINK_WIDTH - 1) : 0] pci_exp_rxp,
	input  [(PL_LINK_CAP_MAX_LINK_WIDTH - 1) : 0] pci_exp_rxn,
//	(* DONT_TOUCH = "TRUE" *) input emcclk,
  	
	input sys_clk_p,
	input sys_clk_n,
	input sys_reset_n,
	
	Adapter2Arbiter_send send [SEND_CHANNELS],
	Adapter2Arbiter_receive receive [RECEIVE_CHANNELS],
	
	output logic [7:0] leds,
	input logic debugButton,
	
	output logic sys_clk,
	output logic user_clk,
	output logic user_reset,
	output logic soft_reset,
	output logic [CHANNELS-1:0] channel_reset
);

logic reset;

wire user_link_up;

logic [27:0] clk_counter;

always_ff @(posedge user_clk) begin
	if(~sys_reset_n) begin
		clk_counter <= 0;
	end else begin
		clk_counter <= clk_counter +1;
	end
end

assign leds[0] = user_link_up;
assign leds[1] = clk_counter[26];
assign leds[2] = sys_reset_n;
assign leds[3] = clk_counter[27];
//Generate clock 
IBUFDS_GTE2 refclk_ibuf (.O(sys_clk), .ODIV2(), .I(sys_clk_p), .CEB(1'b0), .IB(sys_clk_n));

//pcie interfaces
pcie_completerRequest    completerRequest();
pcie_completerCompletion completerCompletion();
pcie_requesterRequest    requesterRequest();
pcie_requesterCompletion requesterCompletion();
	
pcie_interrupt pcieInterrupt();
pcie_configurationStatus pcieStatus();
pcie_configuration_flowcontrol pcieConfigurationFlowControl();
pcie_transmitFlowControl pcieTransmitFlowControl();

pcie3_8x pcie3x8_core (
	//PCIe diff pairs
	.pci_exp_txn(pci_exp_txn),                                              // output wire [7 : 0] pci_exp_txn
	.pci_exp_txp(pci_exp_txp),                                              // output wire [7 : 0] pci_exp_txp
	.pci_exp_rxn(pci_exp_rxn),                                              // input wire [7 : 0] pci_exp_rxn
	.pci_exp_rxp(pci_exp_rxp),                                              // input wire [7 : 0] pci_exp_rxp
	
	//clock and GT sharing
	.int_pclk_out_slave(),                                // output wire int_pclk_out_slave
	.int_pipe_rxusrclk_out(),                          // output wire int_pipe_rxusrclk_out
	.int_rxoutclk_out(),                                    // output wire [7 : 0] int_rxoutclk_out
	.int_dclk_out(),                                            // output wire int_dclk_out
	.int_userclk1_out(),                                    // output wire int_userclk1_out
	.int_userclk2_out(),                                    // output wire int_userclk2_out
	.int_oobclk_out(),                                        // output wire int_oobclk_out
	.int_qplllock_out(),                                    // output wire [1 : 0] int_qplllock_out
	.int_qplloutclk_out(),                                // output wire [1 : 0] int_qplloutclk_out
	.int_qplloutrefclk_out(),                          // output wire [1 : 0] int_qplloutrefclk_out
	.int_pclk_sel_slave({PL_LINK_CAP_MAX_LINK_WIDTH{1'b0}}),                                // input wire [7 : 0] int_pclk_sel_slave
	
	//AXI
	.user_clk(user_clk),                                                    // output wire user_clk
	.user_reset(user_reset),                                                // output wire user_reset
	.user_lnk_up(user_link_up),                                              // output wire user_lnk_up
	.user_app_rdy(),                                            // output wire user_app_rdy, only needed for pcie bootstrapping
	
	.s_axis_rq_tlast(requesterRequest.last),                                      // input wire s_axis_rq_tlast
	.s_axis_rq_tdata(requesterRequest.data),                                      // input wire [255 : 0] s_axis_rq_tdata
	.s_axis_rq_tuser(requesterRequest.user),                                      // input wire [59 : 0] s_axis_rq_tuser
	.s_axis_rq_tkeep(requesterRequest.keep),                                      // input wire [7 : 0] s_axis_rq_tkeep
	.s_axis_rq_tready(requesterRequest.ready),                                    // output wire [3 : 0] s_axis_rq_tready
	.s_axis_rq_tvalid(requesterRequest.valid),                                    // input wire s_axis_rq_tvalid
	
	.m_axis_rc_tdata(requesterCompletion.data),                                      // output wire [255 : 0] m_axis_rc_tdata
	.m_axis_rc_tuser(requesterCompletion.user),                                      // output wire [74 : 0] m_axis_rc_tuser
	.m_axis_rc_tlast(requesterCompletion.last),                                      // output wire m_axis_rc_tlast
	.m_axis_rc_tkeep(requesterCompletion.keep),                                      // output wire [7 : 0] m_axis_rc_tkeep
	.m_axis_rc_tvalid(requesterCompletion.valid),                                    // output wire m_axis_rc_tvalid
	.m_axis_rc_tready(requesterCompletion.ready),                                    // input wire [21 : 0] m_axis_rc_tready
	
	.m_axis_cq_tdata(completerRequest.data),                                      // output wire [255 : 0] m_axis_cq_tdata
	.m_axis_cq_tuser(completerRequest.user),                                      // output wire [84 : 0] m_axis_cq_tuser
	.m_axis_cq_tlast(completerRequest.last),                                      // output wire m_axis_cq_tlast
	.m_axis_cq_tkeep(completerRequest.keep),                                      // output wire [7 : 0] m_axis_cq_tkeep
	.m_axis_cq_tvalid(completerRequest.valid),                                    // output wire m_axis_cq_tvalid
	.m_axis_cq_tready(completerRequest.ready),                                    // input wire [21 : 0] m_axis_cq_tready
	
	.s_axis_cc_tdata(completerCompletion.data),                                      // input wire [255 : 0] s_axis_cc_tdata
	.s_axis_cc_tuser(completerCompletion.user),                                      // input wire [32 : 0] s_axis_cc_tuser
	.s_axis_cc_tlast(completerCompletion.last),                                      // input wire s_axis_cc_tlast
	.s_axis_cc_tkeep(completerCompletion.keep),                                      // input wire [7 : 0] s_axis_cc_tkeep
	.s_axis_cc_tvalid(completerCompletion.valid),                                    // input wire s_axis_cc_tvalid
	.s_axis_cc_tready(completerCompletion.ready),                                    // output wire [3 : 0] s_axis_cc_tready
	
	.cfg_phy_link_down(pcieStatus.physicalLinkDown),                                                // output wire cfg_phy_link_down                       
    .cfg_phy_link_status(pcieStatus.physicalLinkState),                                             // output wire [1 : 0] cfg_phy_link_status             
    .cfg_negotiated_width(pcieStatus.negotiatedWidth),                                              // output wire [3 : 0] cfg_negotiated_width            
    .cfg_current_speed(pcieStatus.speed),                                                           // output wire [2 : 0] cfg_current_speed               
    .cfg_max_payload(pcieStatus.maxPayloadSize),                                                    // output wire [2 : 0] cfg_max_payload                 
    .cfg_max_read_req(pcieStatus.maxReadRequestSize),                                              // output wire [2 : 0] cfg_max_read_req                
    .cfg_function_status(pcieStatus.functionStatus),                                                // output wire [7 : 0] cfg_function_status             
    .cfg_function_power_state(pcieStatus.functionPower),                                            // output wire [5 : 0] cfg_function_power_state        
    .cfg_vf_status(pcieStatus.virtualFunctionStatus),                                               // output wire [11 : 0] cfg_vf_status                  
    .cfg_vf_power_state(pcieStatus.virtualFunctionPower),                                           // output wire [17 : 0] cfg_vf_power_state             
    .cfg_link_power_state(pcieStatus.linkPowerState),                                               // output wire [1 : 0] cfg_link_power_state            
    .cfg_err_cor_out(pcieStatus.error_correctable),                                                 // output wire cfg_err_cor_out                         
    .cfg_err_nonfatal_out(pcieStatus.error_nonfatal),                                               // output wire cfg_err_nonfatal_out                    
    .cfg_err_fatal_out(pcieStatus.error_fatal),                                                     // output wire cfg_err_fatal_out                       
    .cfg_ltr_enable(pcieStatus.latencyToleranceReporting),                                          // output wire cfg_ltr_enable                          
    .cfg_ltssm_state(pcieStatus.LTSSM_state),                                                       // output wire [5 : 0] cfg_ltssm_state                 
    .cfg_rcb_status(pcieStatus.rcb_state),                                                          // output wire [1 : 0] cfg_rcb_status                  
    .cfg_dpa_substate_change(pcieStatus.dynamicPowerAllocation_substateChange),                     // output wire [1 : 0] cfg_dpa_substate_change         
    .cfg_obff_enable(pcieStatus.optimizedBufferFlush_control),                                      // output wire [1 : 0] cfg_obff_enable                 
    .cfg_pl_status_change(pcieStatus.pl_status_change),                                             // output wire cfg_pl_status_change                    
    .cfg_tph_requester_enable(pcieStatus.tph_requester_enable),                                     // output wire [1 : 0] cfg_tph_requester_enable        
    .cfg_tph_st_mode(pcieStatus.tph_st_mode),                                                       // output wire [5 : 0] cfg_tph_st_mode                 
    .cfg_vf_tph_requester_enable(pcieStatus.virtualFunction_tph_requesterEnable),                   // output wire [5 : 0] cfg_vf_tph_requester_enable     
    .cfg_vf_tph_st_mode(pcieStatus.virtualFunction_tph_st_mode),                                    // output wire [17 : 0] cfg_vf_tph_st_mode             

    //TODO: five unconnected ports / one constant
	.pcie_rq_seq_num(),                                      // output wire [3 : 0] pcie_rq_seq_num
	.pcie_rq_seq_num_vld(),                              // output wire pcie_rq_seq_num_vld
	.pcie_rq_tag(),                                              // output wire [5 : 0] pcie_rq_tag
	.pcie_rq_tag_vld(),
	
	.pcie_cq_np_req(1),   //no Backpressure on completer requests                 // input wire pcie_cq_np_req
	.pcie_cq_np_req_count(),                            // output wire [5 : 0] pcie_cq_np_req_count
	
	.pcie_tfc_nph_av(pcieTransmitFlowControl.nonPostedHeaderCredits),                                      // output wire [1 : 0] pcie_tfc_nph_av
	.pcie_tfc_npd_av(pcieTransmitFlowControl.nonPostedDataCredits),                                      // output wire [1 : 0] pcie_tfc_npd_av
	
	.cfg_fc_ph(pcieConfigurationFlowControl.postedHeader),                                                  // output wire [7 : 0] cfg_fc_ph
	.cfg_fc_pd(pcieConfigurationFlowControl.postedData),                                                  // output wire [11 : 0] cfg_fc_pd
	.cfg_fc_nph(pcieConfigurationFlowControl.nonPostedHeader),                                                // output wire [7 : 0] cfg_fc_nph
	.cfg_fc_npd(pcieConfigurationFlowControl.nonPostedData),                                                // output wire [11 : 0] cfg_fc_npd
	.cfg_fc_cplh(pcieConfigurationFlowControl.completionHeader),                                              // output wire [7 : 0] cfg_fc_cplh
	.cfg_fc_cpld(pcieConfigurationFlowControl.completionData),                                              // output wire [11 : 0] cfg_fc_cpld
	.cfg_fc_sel(pcieConfigurationFlowControl.informationSelect),                                                // input wire [2 : 0] cfg_fc_sel
	
	.cfg_interrupt_int(pcieInterrupt.legacy_interrupt),                                  // input wire [3 : 0] cfg_interrupt_int
	.cfg_interrupt_pending(pcieInterrupt.legacy_pending),                          // input wire [1 : 0] cfg_interrupt_pending
	.cfg_interrupt_sent(pcieInterrupt.legacy_sent),                                // output wire cfg_interrupt_sent
	.cfg_interrupt_msi_enable(pcieInterrupt.enable),                    // output wire [1 : 0] cfg_interrupt_msi_enable
	.cfg_interrupt_msi_vf_enable(pcieInterrupt.vf_enable),              // output wire [5 : 0] cfg_interrupt_msi_vf_enable
	.cfg_interrupt_msi_mmenable(pcieInterrupt.mmenable),                // output wire [5 : 0] cfg_interrupt_msi_mmenable
	.cfg_interrupt_msi_mask_update(pcieInterrupt.mask_update),          // output wire cfg_interrupt_msi_mask_update
	.cfg_interrupt_msi_data(pcieInterrupt.data),                        // output wire [31 : 0] cfg_interrupt_msi_data
	.cfg_interrupt_msi_select(pcieInterrupt.select),                    // input wire [3 : 0] cfg_interrupt_msi_select
	.cfg_interrupt_msi_int(pcieInterrupt.interruptVector),                          // input wire [31 : 0] cfg_interrupt_msi_int
	.cfg_interrupt_msi_pending_status(pcieInterrupt.pending_status),    // input wire [63 : 0] cfg_interrupt_msi_pending_status
	.cfg_interrupt_msi_sent(pcieInterrupt.sent),                        // output wire cfg_interrupt_msi_sent
	.cfg_interrupt_msi_fail(pcieInterrupt.fail),                        // output wire cfg_interrupt_msi_fail
	.cfg_interrupt_msi_attr(pcieInterrupt.attr),                        // input wire [2 : 0] cfg_interrupt_msi_attr
	.cfg_interrupt_msi_tph_present(pcieInterrupt.tph_present),          // input wire cfg_interrupt_msi_tph_present
	.cfg_interrupt_msi_tph_type(pcieInterrupt.tph_type),                // input wire [1 : 0] cfg_interrupt_msi_tph_type
	.cfg_interrupt_msi_tph_st_tag(pcieInterrupt.tph_st_tag),            // input wire [8 : 0] cfg_interrupt_msi_tph_st_tag
	.cfg_interrupt_msi_function_number(pcieInterrupt.function_number),  // input wire [2 : 0] cfg_interrupt_msi_function_number
	
	.sys_clk(sys_clk),                                                      // input wire sys_clk
	.sys_reset(~sys_reset_n)                                                  // input wire sys_reset
);

//interface
registerfileConnector #(
	.CHANNELS(CHANNELS),
	.CHANNEL_MODES(CHANNEL_MODES),
	.CHANNELADDRESSBITS(CHANNELADDRESSBITS),
	.ADDRESSBIT_OFFSET(ADDRESSBIT_OFFSET)
) registerFileBus();


assign channel_reset = registerFileBus.channelReset;
assign soft_reset    = registerFileBus.systemReset;

assign reset = registerFileBus.systemReset || user_reset;
// Should rather take the reset status of the different custom cores.
//assign registerFileBus.systemStatus = user_link_up;

requestEngineConnect #(
	.DATAWIDTH(INTERFACEWIDTH),
	.CHANNELS(CHANNELS),
	.CHANNEL_MODES(CHANNEL_MODES)
)requestArbiterConnect();

//My modules

registerfile #(
	.CHANNELS(CHANNELS),
	.CHANNEL_MODES(CHANNEL_MODES),
	.CHANNEL_TYPES(CHANNEL_TYPES),
	.CHANNELADDRESSBITS(CHANNELADDRESSBITS),
	.ADDRESSBIT_OFFSET(ADDRESSBIT_OFFSET)
)pcieRegister (
	.clk(user_clk),
	.reset(reset),
	.leds(leds[7:4]),
	.port(registerFileBus),
	.pcieStatus(pcieStatus)
);

completionEngine completer(
	.clk(user_clk),
	.reset(reset),
	.completerRequest(completerRequest),
	.completerCompletion(completerCompletion),
	.registerfile(registerFileBus)
);

requestEngine #(
	.CHANNELS(CHANNELS),
	.CHANNEL_MODES(CHANNEL_MODES)
) requester (
	.clk(user_clk),
	.reset(reset),
	.requesterCompletion(requesterCompletion),
	.requesterRequest(requesterRequest),
	
	.interrupt(pcieInterrupt),
	.flowcontrol(pcieConfigurationFlowControl),
	
	.link(requestArbiterConnect)
);

arbiter #(
	.CHANNELS(CHANNELS),
	.CHANNEL_MODES(CHANNEL_MODES),
	.DATAWIDTH(INTERFACEWIDTH)
) arbiter (
	.clk(user_clk),
	.reset(reset),
	.registerfile(registerFileBus.arbiter),
	.requestEngine(requestArbiterConnect.arbiter),
	.sendLink(send),
	.receiveLink(receive),
	.configurationStatus(pcieStatus),
	.debugButton(debugButton)
);

endmodule