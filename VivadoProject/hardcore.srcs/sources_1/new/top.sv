//SAMPLE SYSTEM
import hardcoreConfig::*;

module top # (
	parameter PL_LINK_CAP_MAX_LINK_WIDTH = 8
) (
	output [(PL_LINK_CAP_MAX_LINK_WIDTH - 1) : 0] pci_exp_txp,
	output [(PL_LINK_CAP_MAX_LINK_WIDTH - 1) : 0] pci_exp_txn,
	input  [(PL_LINK_CAP_MAX_LINK_WIDTH - 1) : 0] pci_exp_rxp,
	input  [(PL_LINK_CAP_MAX_LINK_WIDTH - 1) : 0] pci_exp_rxn,
//	(* DONT_TOUCH = "TRUE" *) input emcclk,
  	
	input sys_clk_p,
	input sys_clk_n,
	input sys_reset_n,
	
	output [7:0] leds,
	input centerButton
);
localparam INTERFACEWIDTH = pcieInterfaces::INTERFACEWIDTH;
	
localparam int unsigned CHANNELS = 2;
localparam hardcoreConfig::channelMode_t [0:CHANNELS-1] CHANNEL_MODES = '{CM_READ_ONLY, CM_WRITE_ONLY}; //, CM_READ_ONLY, CM_WRITE_ONLY}; //,CM_READ_ONLY, CM_WRITE_ONLY, CM_READ_ONLY, CM_WRITE_ONLY
localparam hardcoreConfig::channelType_t [0:CHANNELS-1] CHANNEL_TYPES = '{CT_INTERFPGA, CT_INTERFPGA}; //, CT_GENERIC, CT_GENERIC}; //,CT_GENERIC, CT_GENERIC, CT_GENERIC, CT_GENERIC
localparam int unsigned SEND_CHANNELS     = hardcoreConfig::channelInfoParser #(CHANNELS)::channelModeCount(CHANNEL_MODES, hardcoreConfig::CM_READ_ONLY);
localparam int unsigned RECEIVE_CHANNELS  = hardcoreConfig::channelInfoParser #(CHANNELS)::channelModeCount(CHANNEL_MODES, hardcoreConfig::CM_WRITE_ONLY);

//TODO: remove
logic [7:0] ledCopy;
	
//always_comb begin
assign leds[1:0] = ledCopy[1:0];
assign leds[2] = centerButton;
assign leds[7:3] = ledCopy[7:3];
//end

logic user_clk;
logic [CHANNELS-1:0] channel_reset;

Adapter2Arbiter_send #(
	.DATAWIDTH(INTERFACEWIDTH)
) sendHarness [SEND_CHANNELS]();
	
Adapter2Arbiter_receive #(
	.DATAWIDTH(INTERFACEWIDTH)
) receiveHarness [RECEIVE_CHANNELS]();	

hardcore # (
	.PL_LINK_CAP_MAX_LINK_WIDTH(8),
	.CHANNELS(CHANNELS),
	.CHANNEL_MODES(CHANNEL_MODES),
	.CHANNEL_TYPES(CHANNEL_TYPES)
) pciBaseSystem (
	.pci_exp_txp(pci_exp_txp),
	.pci_exp_txn(pci_exp_txn),
	.pci_exp_rxp(pci_exp_rxp),
	.pci_exp_rxn(pci_exp_rxn),
	
	.sys_clk_p  (sys_clk_p),
	.sys_clk_n  (sys_clk_n),
	.sys_reset_n(sys_reset_n),
	
	.send(sendHarness.arbiter),
	.receive(receiveHarness.arbiter),
	
	.sys_clk(),
	.user_clk(user_clk),
	.user_reset(),
	.channel_reset(channel_reset),
	
	.leds       (ledCopy),
	.debugButton(centerButton)
);	


userModules #(
	.CHANNELS (CHANNELS),
	.CHANNEL_MODES(CHANNEL_MODES),
	.CHANNEL_TYPES(CHANNEL_TYPES),
	.DATAWIDTH(INTERFACEWIDTH)
)
userModulesInstantiator (
	.clk(user_clk),
	.reset(channel_reset),
	.send(sendHarness.adapter),
	.receive(receiveHarness.adapter)
);

endmodule