import pcieInterfaces::*;
import hardcoreConfig::*;

module userModules #(
	parameter int unsigned CHANNELS = 4,
	parameter hardcoreConfig::channelMode_t [0:CHANNELS-1] CHANNEL_MODES = '{default: hardcoreConfig::CM_NOT_PRESENT},
	parameter hardcoreConfig::channelType_t [0:CHANNELS-1] CHANNEL_TYPES = '{default: hardcoreConfig::CT_GENERIC},
	parameter int unsigned SEND_CHANNELS = hardcoreConfig::channelInfoParser #(CHANNELS)::channelModeCount(CHANNEL_MODES, hardcoreConfig::CM_READ_ONLY),
	parameter int unsigned RECEIVE_CHANNELS  = hardcoreConfig::channelInfoParser #(CHANNELS)::channelModeCount(CHANNEL_MODES, hardcoreConfig::CM_WRITE_ONLY),
	parameter DATAWIDTH = 256
)(
	input logic clk,
	input logic [CHANNELS-1:0] reset,
	Adapter2Arbiter_send #(
		.DATAWIDTH(DATAWIDTH)
	) send[SEND_CHANNELS-1:0],
		
	Adapter2Arbiter_receive #(
		.DATAWIDTH(DATAWIDTH)
	) receive[RECEIVE_CHANNELS-1:0]
);
	
localparam SINK_AND_SOURCE = 0;
localparam LOOPBACK_START_INDEX = SINK_AND_SOURCE ? 1 : 0;
	
generate
if(SINK_AND_SOURCE) begin
	sink testSink(
		.clk        (clk),
		.reset      (reset),
		.arbiterReceive(receive[0])
	);
	
	source testSource (
		.clk        (clk),
		.reset      (reset),
		.arbiterSend(send[0])
	);
end
endgenerate
	
//For testing we just instantiate the loopback module multiple time
//For easy testing we just assume that the channels are allocated alternatingliy as read, write
for(genvar i=LOOPBACK_START_INDEX; i<SEND_CHANNELS; i++) begin
	loopback loopbackDevice (
		.clk           (clk),
		.reset         (reset[i]),
		.arbiterSend   (send[i]),
		.arbiterReceive(receive[i])
	);
end
	
endmodule
