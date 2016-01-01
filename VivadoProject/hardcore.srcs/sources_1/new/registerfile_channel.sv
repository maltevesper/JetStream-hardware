import fifoPkg::*;

//TODO:own file?
interface channelCommandRegisterConnector ; /*# (
		parameter ADDRESSBITS = 3
	);*/
	
	localparam int ADDRESSBITS = 3;
	localparam int REGISTERWIDTH = 32;
	localparam int PCADDRESSWIDTH = 64;

	logic [REGISTERWIDTH-1:0] dataWrite;
	logic [REGISTERWIDTH-1:0] dataRead;
	logic write;

	logic [ADDRESSBITS-1:0] writeAddress;
	logic [ADDRESSBITS-1:0] readAddress;

	logic consumeCommand;

	logic [PCADDRESSWIDTH-1:0] commandAddress;
	logic [REGISTERWIDTH-1:0] commandSize;
	logic commandValid;

	//logic [63:0] lastReadFlowdifference; //over/underflow (see flags in the status register to decide

	modport core(
		input  dataWrite,
		output dataRead,
		input  write,
		input  readAddress,
		input  writeAddress,

		input  consumeCommand,
		
		output commandValid,
		output commandSize,
		output commandAddress
	);

	modport registerfile(
		output dataWrite,
		input  dataRead,
		output write,
		output readAddress,
		output writeAddress,

		output consumeCommand,

		input  commandValid,
		input  commandSize,
		input  commandAddress
	);
endinterface

module channelCommandRegister #(
		//parameter READCHANNEL   = 1,
		parameter DEPTH         = 2,
		parameter REGISTERWIDTH =32,
		parameter hardcoreConfig::channelType_t CHANNELTYPE = hardcoreConfig::CT_GENERIC,
		parameter hardcoreConfig::channelMode_t CHANNELMODE = hardcoreConfig::CM_BIDIRECTIONAL
	)(
		input logic clk,
		input logic reset,
		channelCommandRegisterConnector.core port,
		output logic [3:0] leds
	);

	const logic [$left(port.writeAddress):$right(port.writeAddress)] REG_FPGAADDRESS_HIGH = 0;
	const logic [$left(port.writeAddress):$right(port.writeAddress)] REG_FPGAADDRESS_LOW  = 1;
	
	const logic [$left(port.writeAddress):$right(port.writeAddress)] REG_PCADDRESS_HIGH   = 2;
	const logic [$left(port.writeAddress):$right(port.writeAddress)] REG_PCADDRESS_LOW    = 3;
	
	const logic [$left(port.writeAddress):$right(port.writeAddress)] REG_LASTSIZE         = 4;
	const logic [$left(port.writeAddress):$right(port.writeAddress)] REG_CONTROL          = 5;
	//const logic [$left(port.address):$right(port.address)] REG_     =   ;

	
	logic highWordSet_comb;
	logic highWordSet_reg;
	
	typedef struct packed {
		logic circle;
	} controlFlags_t;
	
	typedef union packed {
		logic [REGISTERWIDTH-1:0] register;
		
		struct packed {
			logic [15:0] queueLength;
			logic [REGISTERWIDTH-1-$bits(controlFlags_t)-$bits(hardcoreConfig::channelMode_t)-$bits(hardcoreConfig::channelType_t)-$bits(queueLength):0] padding;
			controlFlags_t flags;
			hardcoreConfig::channelMode_t channelMode;
			hardcoreConfig::channelType_t channelType;
		} components;
	} controlRegister_t;
	
	controlFlags_t flags_comb;
	controlFlags_t flags_reg;

	fifoConnect #(
		.WIDTH(REGISTERWIDTH),
		.DEPTH(DEPTH)
		) pcAddressHigh();
	
	fifoConnect #(
		.WIDTH(REGISTERWIDTH),
		.DEPTH(DEPTH)
	) pcAddressLow();

	fifo #(
		.WIDTH(REGISTERWIDTH),
		.DEPTH(DEPTH),
		.OUTPUTS(FIFO_NONE)
	) pcAddressHighFifo(
		.clk(clk),
		.circular(flags_reg.circle),
		.link(pcAddressHigh),
		.reset(reset)
	);

	fifo #(
		.WIDTH(REGISTERWIDTH),
		.DEPTH(DEPTH),
		.OUTPUTS(FIFO_VALID)
	) pcAddressLowFifo(
		.clk(clk),
		.circular(flags_reg.circle),
		.link(pcAddressLow),
		.reset(reset)
	);
	
	fifoConnect #(
		.WIDTH(REGISTERWIDTH),
		.DEPTH(DEPTH)
	) size();
	
	fifo #(
		.WIDTH(REGISTERWIDTH),
		.DEPTH(DEPTH),
		.OUTPUTS(FIFO_VALID)
	) sizeFifo(
		.clk(clk),
		.circular(flags_reg.circle),
		.link(size),
		.reset(reset)
	);

assign port.commandValid   = size.fillStatus.valid && pcAddressLow.fillStatus.valid; //implise pcAddressHigh is valid.
assign port.commandAddress = {pcAddressHigh.dataout, pcAddressLow.dataout};
assign port.commandSize    = size.dataout;
	
assign leds[0] = size.fillStatus.valid;
assign leds[1] = pcAddressLow.fillStatus.valid;
assign leds[2] = port.commandValid;
assign leds[3] = 1;

//== TIMING CLOSURE ======
logic pcAddressHighDelay_reg;
logic pcAddressHighDelay_comb;
logic [REGISTERWIDTH-1:0] dataDelay_reg;	
logic [REGISTERWIDTH-1:0] dataDelay_comb;

always_ff @(posedge clk) begin :  registers
	if(reset) begin
		highWordSet_reg <= 0;
		pcAddressHighDelay_reg <= 0;
	end else begin
		highWordSet_reg <= highWordSet_comb;
		flags_reg     <= flags_comb;
		pcAddressHighDelay_reg <= pcAddressHighDelay_comb;
	end
	
	dataDelay_reg <= dataDelay_comb;
end

always_comb begin : write
	pcAddressHigh.write  = 0;
	pcAddressHigh.datain = 0;
	
	pcAddressLow.write   = 0;
	pcAddressLow.datain  = port.dataWrite;

	size.write                  = 0;
	size.datain                 = port.dataWrite;

	highWordSet_comb = highWordSet_reg;
	flags_comb     = flags_reg;
	
	pcAddressHighDelay_comb = 0;
	
	dataDelay_comb = dataDelay_reg;
	
	pcAddressHigh.datain = dataDelay_reg;
	pcAddressHigh.write  = pcAddressHighDelay_reg;// || (port.write && port.writeAddress == REG_PCADDRESS_LOW && !highWordSet_reg); //breaks timing, done below in case statement

	if(port.write) begin
		unique case(port.writeAddress)
			REG_FPGAADDRESS_HIGH: begin
				//TODO: UNIMPLEMENTED
			end
			REG_FPGAADDRESS_LOW: begin
				//TODO: UNIMPLEMENTED
			end
			REG_PCADDRESS_HIGH: begin
				highWordSet_comb = 1;
				
				//pcAddressHigh.datain = port.dataWrite;
				//pcAddressHigh.write  = 1;
				pcAddressHighDelay_comb = 1;
				dataDelay_comb = port.dataWrite;
				
				//TODO: stall if full?
			end
			REG_PCADDRESS_LOW: begin
				if(!highWordSet_reg) begin
					pcAddressHigh.datain = 0;
					pcAddressHigh.write  = 1;
				end
				
				highWordSet_comb = 0;
				dataDelay_comb   = '0;

				pcAddressLow.write  = 1;
				//TODO:stall if full?
			end
			REG_LASTSIZE: begin
				size.write = 1;
			end
			REG_CONTROL: begin
				automatic controlRegister_t data = controlRegister_t'(port.dataWrite);
				
				flags_comb = data.components.flags;
			end

		endcase
	end
end

always_comb begin : read
	unique case(port.readAddress)
		REG_FPGAADDRESS_HIGH: begin
			//TODO UNIMPLEMENTED
			port.dataRead = '0;
		end
		REG_FPGAADDRESS_LOW: begin
			//TODO UNIMPLEMENTED
			port.dataRead = '0;
		end
		REG_PCADDRESS_HIGH: begin
			port.dataRead = pcAddressHigh.dataout;
		end
		REG_PCADDRESS_LOW: begin
			port.dataRead = pcAddressLow.dataout;
		end
		REG_LASTSIZE: begin
			port.dataRead = size.dataout;
		end
		REG_CONTROL: begin
			controlRegister_t data;
			
			data.components.queueLength = size.fillLevel;
			data.components.channelType = CHANNELTYPE;
			data.components.channelMode = CHANNELMODE;
			data.components.flags       = flags_reg;
			data.components.padding     = 0;
			
			port.dataRead = data;
		end
		default: begin
			port.dataRead = '0;
		end
	endcase
end

always_comb begin : processCommand
	pcAddressHigh.read = port.consumeCommand;
	pcAddressLow.read  = port.consumeCommand;
	size.read          = port.consumeCommand;
end

endmodule