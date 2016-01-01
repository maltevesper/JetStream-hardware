interface registerfileConnector # (
		parameter int CHANNELS = 2,
		parameter hardcoreConfig::channelMode_t [0:CHANNELS-1] CHANNEL_MODES = '{default: hardcoreConfig::CM_NOT_PRESENT},
		parameter int CHANNELADDRESSBITS = 3,
		parameter int ADDRESSBIT_OFFSET = 2
	);

//TODO: this should be in one place for the interface and the module. SAME goes for Registerbits, and co
	localparam int MAXCHANNELS           = 26;
	localparam int BASEREGISTERFACTOR = 2;
	localparam int ADDRESSWIDTH = 64;
	localparam int REGISTERBITS     = 32;
	//localparam int CHANNELBITS  = $clog2(CHANNELS);
	localparam int ADDRESSBITS = CHANNELADDRESSBITS + $clog2(MAXCHANNELS+BASEREGISTERFACTOR); //2**ADDRESSBITS REGISTERS available

	logic [REGISTERBITS-1:0] dataWrite;
	logic [REGISTERBITS-1:0] dataRead;
	logic  [ADDRESSBITS + ADDRESSBIT_OFFSET - 1:ADDRESSBIT_OFFSET] addressWrite; //4096/64 (max registerdepth over registerwidth )
	logic  [ADDRESSBITS + ADDRESSBIT_OFFSET - 1:ADDRESSBIT_OFFSET] addressRead; //4096/64 (max registerdepth over registerwidth )
	logic write;
	logic stall;

	logic                    systemReset;
	logic [CHANNELS-1:0]     channelReset; //TODO would unpacked work?

	logic                    systemStatus;
	logic [CHANNELS-1:0]     channelStatus; //TODO would unpacked work?

	logic [REGISTERBITS-1:0] commandSize[CHANNELS-1:0];
	logic [ADDRESSWIDTH-1:0] commandAddress[CHANNELS-1:0];
	logic [CHANNELS-1:0]     commandValid; //TODO would unpacked work?
	logic [CHANNELS-1:0]     commandConsumed; //TODO would unpacked work?
	logic [CHANNELS-1:0]     commandCompleted; //TODO would unpacked work?

	//becomes only valid if Overflow or Underflow are asserted
	//logic [SIZEBITS-1:0]     writeActuallyDone[CHANNELS-1:0];
	//logic [CHANNELS-1:0]     writeDoneOverflow;
	//logic [CHANNELS-1:0]     writeDoneUnderflow;

	//logic [SIZEBITS-1:0]     readSize[CHANNELS-1:0];
	//logic [CHANNELS-1:0]     readValid;
	//logic [CHANNELS-1:0]     readDone;

	modport core(
		input  dataWrite,
		output dataRead,
		input  addressWrite,
		input  addressRead,
		input  write,

		input  systemStatus,
		input  channelStatus,
		output systemReset,
		output channelReset,

		output commandSize,
		output commandAddress,
		output commandValid,
		input  commandConsumed,
		input  commandCompleted

		/*input  writeActuallyDone,
		input  writeDoneOverflow,
		input  writeDoneUnderflow,

		output readSize,
		output readValid,
		input  readDone*/
	);

	modport userLogic(
		output dataWrite,
		input  dataRead,
		output addressWrite,
		output addressRead,
		output write,
		input  channelReset,
		output channelStatus
	);

	modport arbiter(
		input  systemReset,
		input  channelReset,

		input  commandSize,
		input  commandAddress,
		input  commandValid,
		output commandConsumed,
		output commandCompleted
		/*output writeActuallyDone,

		input  readSize,
		input  readValid,
		output readDone*/
	);
endinterface

localparam int PCIE_SUBSYSTEM_VERSION = 3;

module registerfile # (
		parameter int CHANNELS           =  2,
		parameter hardcoreConfig::channelMode_t [0:CHANNELS-1] CHANNEL_MODES = '{default: hardcoreConfig::CM_NOT_PRESENT},
		parameter hardcoreConfig::channelType_t [0:CHANNELS-1] CHANNEL_TYPES = '{default: hardcoreConfig::CT_GENERIC},
		parameter int DEPTH              =  8, //depth in circular buffers for the channels
		parameter int REGISTERWIDTH      = 32,
		parameter int CHANNELADDRESSBITS =  3,
		parameter int SINKCHANNELS       =  0,
		parameter int ADDRESSBIT_OFFSET  =  2
	)(
		input logic clk,
		input logic reset,
		registerfileConnector.core port,
		pcie_configurationStatus.userLogic pcieStatus,
		output logic [3:0] leds
	);

	localparam int BASEREGISTERFACTOR    =  2; //there will be (2**CHANNELADDRESSBITS)*BASEREGISTERFACTOR registers before we get to an actual CHANNEL
	localparam int MAXCHANNELS           = 26;
	localparam int COMPLETIONCOUNTERBITS =  4; //must devide REGISTERWIDTH without a remainder TODO assertion for this
	localparam int COMPLETIONREGISTERS   = MAXCHANNELS*COMPLETIONCOUNTERBITS/REGISTERWIDTH + (MAXCHANNELS*COMPLETIONCOUNTERBITS%REGISTERWIDTH?1:0); //==4 FUCK XILINX for not supporting ceil

	const logic [$left(port.addressWrite):$right(port.addressWrite)] REG_VERSION                 =   0;
	const logic [$left(port.addressWrite):$right(port.addressWrite)] REG_SYSTEM                  =   1;
	const logic [$left(port.addressWrite):$right(port.addressWrite)] REG_SCRATCHPAD              =   2;
	
	const logic [$left(port.addressWrite):$right(port.addressWrite)] REG_BOARDADDR_HIGH          =   3;
	const logic [$left(port.addressWrite):$right(port.addressWrite)] REG_BOARDADDR_LOW           =   4;
	
	const logic [$left(port.addressWrite):$right(port.addressWrite)] REG_SINKCHANNELS            =   5;
	
	const logic [$left(port.addressWrite):$right(port.addressWrite)] REG_MAX_PAYLOAD             =   6;
	const logic [$left(port.addressWrite):$right(port.addressWrite)] REG_MAX_REQUEST             =   7;
	
	const logic [$left(port.addressWrite):$right(port.addressWrite)] REG_COMPLETION_COUNTER_BASE =   8; //TODO assert this + COMPLETIONREGISTERS is smaller than REG_CHANNELBASE
	
	const logic [$left(port.addressWrite):$right(port.addressWrite)] REG_CHANNELBASE = BASEREGISTERFACTOR*(2**CHANNELADDRESSBITS); //WARNING: THE CODE ABUSES THAT THE CHANNELBASE IS EVERYTHING WITH ITS BITS BEFORE THE CHANNELBITS 0000. ADJUST THE READCODE BELOW IF YOU CHANGE THIS
	const logic [$left(port.addressWrite):$right(port.addressWrite)] REG_USERBASE    = REG_CHANNELBASE + MAXCHANNELS*(2**CHANNELADDRESSBITS);
	
	const logic [$left(REG_CHANNELBASE):$right(REG_CHANNELBASE)+CHANNELADDRESSBITS] CHANNELBASE_INDEXOFFSET = REG_CHANNELBASE[$left(REG_CHANNELBASE):$right(REG_CHANNELBASE)+CHANNELADDRESSBITS];
//RESERVED_REG

	
	
	// ## SystemRegister
	typedef union packed {
		logic [REGISTERWIDTH-1:0] register;
		
		struct packed {
			logic [REGISTERWIDTH-1:CHANNELS] padding_0;
			logic [CHANNELS-1:0] channel;
		} channels;
		
		struct packed {
			logic [4:0]  channels;
			logic status;
			logic [MAXCHANNELS-1:0] padding;
		} system;
	} systemRegister_t;

	systemRegister_t systemRegister;
	
	typedef struct packed {
		logic [CHANNELS-1:0] channel;
		logic system;
	} resetRegister_t;
	
	resetRegister_t reset_reg;
	
	// ## ScratchpadRegister
	logic [REGISTERWIDTH-1:0] scratchpad_reg;
	
	// ## Device BUs addr register
	
	logic [REGISTERWIDTH-1:0] busAddress_low;
	logic [REGISTERWIDTH-1:0] busAddress_high;

	// == Completion Counter connector
	logic [COMPLETIONREGISTERS-1:0][REGISTERWIDTH-1:0] completionCounter;
	logic [COMPLETIONREGISTERS-1:0]                    completionRead;

	logic [REGISTERWIDTH-1:0] channelReadConnector [(2**$clog2(CHANNELS))-1:0];

	// ## Constant assignments
	
	for(genvar i=CHANNELS; i<MAXCHANNELS; i++) begin : as
		assign systemRegister.system.padding[i] = 0;
	end
	
	assign systemRegister.system.channels = CHANNELS;
	
	assign systemRegister.channels.channel = port.channelStatus;
	
	assign systemRegister.system.status = port.systemStatus;
	
	assign port.systemReset  = reset_reg.system;
	assign port.channelReset = reset_reg.channel;
	
// synthesis translate_off
	initial begin
		assert(CHANNELS + 6 <= REGISTERWIDTH) else $error(
			"To many channels specified. Maximum REGISTERBITS-6.");
	end
// synthesis translate_on

	logic [3:0] ledForward [3:0];

	for(genvar i=0; i<CHANNELS; i++) begin : channels
		channelCommandRegisterConnector channel();
		
		channelCommandRegister #(
			.DEPTH        (DEPTH),
			.REGISTERWIDTH(REGISTERWIDTH),
			.CHANNELTYPE  (CHANNEL_TYPES[i]),
			.CHANNELMODE  (CHANNEL_MODES[i])
		) channelRegister(
			.clk  (clk),
			.reset(reset),
			.port (channels[i].channel),
			.leds(ledForward[i])
		);
		
		assign channels[i].channel.readAddress    = port.addressRead[CHANNELADDRESSBITS + ADDRESSBIT_OFFSET - 1:ADDRESSBIT_OFFSET];
		assign channels[i].channel.writeAddress   = port.addressWrite[CHANNELADDRESSBITS + ADDRESSBIT_OFFSET - 1:ADDRESSBIT_OFFSET];
		assign channels[i].channel.dataWrite      = port.dataWrite;

		assign channels[i].channel.write          = port.addressWrite[$left(port.addressWrite):$right(port.addressWrite)+CHANNELADDRESSBITS] == i + CHANNELBASE_INDEXOFFSET;
		assign channels[i].channel.consumeCommand = port.commandConsumed[i];

		assign port.commandSize[i]                = channels[i].channel.commandSize;
		assign port.commandAddress[i]             = channels[i].channel.commandAddress;
		assign port.commandValid[i]               = channels[i].channel.commandValid;

		assign channelReadConnector[i]            = channels[i].channel.dataRead;
		
		wire increment;
		wire read;

		clearOnReadCounter #(
			.WIDTH(COMPLETIONCOUNTERBITS)
		)
		u_clearOnReadCounter (
			.clk      (clk),
			.reset    (reset),
			.increment(port.commandCompleted[i]),
			.read     (completionRead[i*COMPLETIONCOUNTERBITS/REGISTERWIDTH]),
			.value    (completionCounter[i*COMPLETIONCOUNTERBITS/REGISTERWIDTH][((i+1)*COMPLETIONCOUNTERBITS-1)%REGISTERWIDTH:i*COMPLETIONCOUNTERBITS%REGISTERWIDTH])
		);
	end
	
	generate
	if(MAXCHANNELS*COMPLETIONCOUNTERBITS%REGISTERWIDTH) begin
		assign completionCounter[COMPLETIONREGISTERS-1][REGISTERWIDTH-1:(MAXCHANNELS*COMPLETIONCOUNTERBITS)%REGISTERWIDTH] = '0;
	end
	endgenerate

	for(genvar i=CHANNELS; i<MAXCHANNELS; ++i) begin
		assign completionCounter[i*COMPLETIONCOUNTERBITS/REGISTERWIDTH][((i+1)*COMPLETIONCOUNTERBITS-1)%REGISTERWIDTH:i*COMPLETIONCOUNTERBITS%REGISTERWIDTH] = '0;
	end
	
	assign leds[3:0] = ledForward[0][3:0];
	
	for(genvar i=CHANNELS; i<2**$clog2(CHANNELS); i++) begin
		assign channelReadConnector[i] = '0;
	end

	always_comb begin : read
		completionRead = '0;
		
		//TODO parallelize this rather than priority encodeing it
		//TODO optimize the comparison? we know that the last digits will always be zero, so it is sufficient to check the front part
		if(port.addressRead < REG_CHANNELBASE) begin
			unique case(port.addressRead)
				REG_VERSION: begin
					port.dataRead = PCIE_SUBSYSTEM_VERSION;
				end
				REG_SYSTEM: begin
					port.dataRead = systemRegister;
				end
				REG_SCRATCHPAD: begin
					port.dataRead = scratchpad_reg;
				end
				REG_BOARDADDR_HIGH: begin
					port.dataRead = busAddress_high;
				end
				REG_BOARDADDR_LOW: begin
					port.dataRead = busAddress_low;
				end
				REG_SINKCHANNELS: begin
					port.dataRead = SINKCHANNELS;
				end
				REG_MAX_PAYLOAD: begin
					port.dataRead = 128 << pcieStatus.maxPayloadSize;//pcieStatus.payloadSizeToInt(pcieStatus.maxPayloadSize);
				end
				REG_MAX_REQUEST: begin
					port.dataRead = 128 << pcieStatus.maxReadRequestSize;//pcieStatus.requestSizeToInt(pcieStatus.maxReadRequestSize);
				end
				default: begin
					port.dataRead = 'hdeadbeef;
				end
			endcase
				
			for(int i=0; i<COMPLETIONREGISTERS; ++i) begin
				if(port.addressRead == REG_COMPLETION_COUNTER_BASE + i) begin
					port.dataRead = completionCounter[i];
					completionRead[i] = 1;
				end
			end
		end else if (port.addressRead[$left(port.addressRead):$right(port.addressRead)+CHANNELADDRESSBITS] < REG_USERBASE[$left(REG_USERBASE):$right(REG_USERBASE)+CHANNELADDRESSBITS]) begin //we are assuming the tool is to stupid to realize that XYZ > 010 is equivalent to XY>01
			if(CHANNELS == 1) begin
				port.dataRead = channelReadConnector[0];
			end else begin
				port.dataRead = channelReadConnector[port.addressRead[$right(port.addressRead)+CHANNELADDRESSBITS+$clog2(CHANNELS + CHANNELBASE_INDEXOFFSET)-1:$right(port.addressRead)+CHANNELADDRESSBITS] - CHANNELBASE_INDEXOFFSET];
			end
		end else begin
			//TODO potential user registers here
			port.dataRead = 'hfacebabe;
		end	
	end
	
	always_ff @(posedge clk) begin : registers
		reset_reg <= 0;

		/*if(reset) begin
			scratchpad_reg <= 0;
		end else begin*/
			if(port.write) begin
				
				unique case(port.addressWrite)
					REG_VERSION: begin
					end
					REG_SYSTEM: begin
						systemRegister_t packedData = systemRegister_t'(port.dataWrite);
						
						reset_reg.system  <= packedData.system.status; //TODO: reset self
						reset_reg.channel <= packedData.channels.channel;
					end
					REG_SCRATCHPAD: begin
						scratchpad_reg <= port.dataWrite;
					end
					REG_BOARDADDR_HIGH: begin
						busAddress_high <= port.dataWrite;
					end
					REG_BOARDADDR_LOW: begin
						busAddress_low <= port.dataWrite;
					end
					REG_SINKCHANNELS: begin
					end
					default: begin
					end
				endcase
			end
		//end
	end
	
endmodule
