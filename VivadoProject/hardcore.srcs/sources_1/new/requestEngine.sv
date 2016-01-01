import pcieInterfaces::*;
import pcie::*;

interface requestEngineConnect # (
		parameter int DATAWIDTH     = pcieInterfaces::INTERFACEWIDTH,
		parameter int BYTEWIDTH     = pcieInterfaces::BYTEBITS,
		parameter int REGISTERWIDTH = 32,
		parameter int ADDRESSWIDTH  = 64,
		parameter int CHANNELS      = 2,
		parameter hardcoreConfig::channelMode_t [0:CHANNELS-1] CHANNEL_MODES = '{default: hardcoreConfig::CM_NOT_PRESENT},
		parameter int unsigned SEND_CHANNELS = hardcoreConfig::channelInfoParser #(CHANNELS)::channelModeCount(CHANNEL_MODES, hardcoreConfig::CM_READ_ONLY),
		parameter int unsigned RECEIVE_CHANNELS  = hardcoreConfig::channelInfoParser #(CHANNELS)::channelModeCount(CHANNEL_MODES, hardcoreConfig::CM_WRITE_ONLY)
	);

	//logic [DATAWIDTH-1:0]     dataReceived;
	//logic [REGISTERWIDTH-1:0] sizeReceived;
	//logic [ADDRESSWIDTH-1:0]  addressReceive;

	logic [DATAWIDTH-1:0]     dataSend;
	logic [$clog2(pcie::MAX_PAYLOAD_BYTES+1)-1:0] sizeSend; //we actually need 0
	logic [ADDRESSWIDTH-1:0]  addressSend;
	logic                     nextSendData;
	logic                     nextSendCommand;
	logic                     validSendCommand;
	logic                     finalizeSendCommand;
	logic                     completedSendCommand;
	logic [$clog2(SEND_CHANNELS)-1:0] nextSourceChannel;
	logic [$clog2(SEND_CHANNELS)-1:0] sourceChannel;
	
	logic [DATAWIDTH-1:0]     dataReceive;
	logic [$clog2(pcie::MAX_REQUEST_SIZE+1)-1:0] sizeReceive; //we actually need 0
	logic [ADDRESSWIDTH-1:0]  addressReceive;
	logic [DATAWIDTH/BYTEWIDTH-1:0] validReceiveData;
	logic                     write;
	logic [$clog2(RECEIVE_CHANNELS)-1:0] channelReceive;
	logic [$clog2(RECEIVE_CHANNELS)-1:0] channelDestination;
	//logic                     readyReceiveData;
	
	logic                     nextReceiveCommand;
	logic                     validReceiveCommand;
	logic                     finalizeReceiveCommand;
	logic                     completedReceiveCommand;
	
	logic [pcie::INTERRUPTVECTORS-1:0] interruptRequests;

	modport core(
//      input  dataReceived,

		input  dataSend,
		input  sizeSend,
		input  addressSend,
		output nextSendData,
		output nextSendCommand,
		input  validSendCommand,
		input  finalizeSendCommand,
		output completedSendCommand,
		input  nextSourceChannel,
		output sourceChannel,

		output dataReceive,
		input  sizeReceive,
		input  addressReceive,
		output validReceiveData,
		output write,
		input  channelReceive,
		output channelDestination,

		output nextReceiveCommand,
		input  validReceiveCommand,
		input  finalizeReceiveCommand,
		output completedReceiveCommand,
		
		input  interruptRequests
	);

	modport arbiter(
		//output  dataReceived,

		output dataSend,
		output sizeSend,
		output addressSend,
		input  nextSendData,
		input  nextSendCommand,
		output validSendCommand,
		output finalizeSendCommand,
		input  completedSendCommand,
		output nextSourceChannel,
		input  sourceChannel,

		input  dataReceive,
		output sizeReceive,
		output addressReceive,
		input  validReceiveData,
		input  write,
		output channelReceive,
		input  channelDestination,

		input  nextReceiveCommand,
		output validReceiveCommand,
		output finalizeReceiveCommand,
		input  completedReceiveCommand,
		
		output interruptRequests
	);
endinterface

module requestEngine #(
	parameter int CHANNELS = 2,
	parameter hardcoreConfig::channelMode_t [0:CHANNELS-1] CHANNEL_MODES = '{default: hardcoreConfig::CM_NOT_PRESENT},
	parameter int unsigned SEND_CHANNELS = hardcoreConfig::channelInfoParser #(CHANNELS)::channelModeCount(CHANNEL_MODES, hardcoreConfig::CM_READ_ONLY),
	parameter int unsigned RECEIVE_CHANNELS  = hardcoreConfig::channelInfoParser #(CHANNELS)::channelModeCount(CHANNEL_MODES, hardcoreConfig::CM_WRITE_ONLY)
)(
	input logic clk,
	input logic reset,
	pcie_requesterCompletion.userLogic requesterCompletion,
	pcie_requesterRequest.userLogic    requesterRequest,

	pcie_interrupt.userLogic interrupt,
	pcie_configuration_flowcontrol.userLogic flowcontrol,

	requestEngineConnect.core link
);
	
	localparam SECOND_HEADER_DW_OFFSET = 4;
	localparam HEADER_DWS = $bits(pcieHeaders::requesterCompletion)/pcie::DWORDBITS;
	

	//== IRQ engine =====
	//--- States -----------
	typedef enum logic [0:0] {INTERRUPT_ENGINE_IDLE, INTERRUPT_ENGINE_WAITING} interuptEngineState_t;
	
	interuptEngineState_t interruptEngineState_comb;
	interuptEngineState_t interruptEngineState_reg;
	
	logic [31:0] interruptPendingPhysicalFunction0_reg;
	
	logic [pcie::INTERRUPTVECTORS-1:0] interrupt_request_comb;
	logic [pcie::INTERRUPTVECTORS-1:0] interrupt_request_reg;
	
	logic [pcie::INTERRUPTVECTORS-1:0] interrupt_request_fired;
	//== Requester ======
	//--- States -----------
	typedef enum logic [1:0] {DISPATCH_IDLE,DISPATCH_SEND,DISPATCH_RECEIVE,DISPATCH_FINALIZE} dispatcherState_t;
	
	dispatcherState_t dispatcherState_reg;
	dispatcherState_t dispatcherState_comb;
	
	//== 

	logic [pcieInterfaces::INTERFACEWIDTH-1:0] request_comb;
	logic [pcieInterfaces::INTERFACEWIDTH-1:0] request_reg;

	logic [127:0] dataAlign_comb;
	logic [127:0] dataAlign_reg;

	logic [$clog2(SEND_CHANNELS)-1:0] sendChannel_comb;
	logic [$clog2(SEND_CHANNELS)-1:0] sendChannel_reg;

	pcieHeaders::dWordCount_t sentDWCounter_comb;
	pcieHeaders::dWordCount_t sentDWCounter_reg;
	
	pcieHeaders::dWordCount_t sentDWCounterPreDecrement_comb;
	pcieHeaders::dWordCount_t sentDWCounterPreDecrement_reg;
	//logic [$bits(pcieHeaders::requesterRequestMemory.dWordCount)-1:0] sentDWCounter_reg;
	
	typedef struct packed {
		logic finalize;
		logic completed;
	} completion_t;
	
	completion_t sendCompletion_comb;
	completion_t sendCompletion_reg;

	//== TagManager ======
	localparam TAG_COUNT = 16; //MUST BE A POWER OF TWO, CURRENTLY XILINX SUPPORTS UP TO 6 TAG BITS => upper limit =64

	logic [TAG_COUNT-1:0] tagAvailable_comb;
	logic [TAG_COUNT-1:0] tagAvailable_reg;
	
	logic tagAvailableFlag_reg;
	
	logic [TAG_COUNT-1:0] makeTagAvailable_0;
	logic [TAG_COUNT-1:0] makeTagAvailable_1;
	
	logic [TAG_COUNT-1:0] useTag;
	logic                 updateTagMemory;
	
	logic [TAG_COUNT-1:0] nextTagMask;
	
	wire [$clog2(TAG_COUNT)-1:0] nextTag;
	
	typedef struct {
		logic [$clog2(RECEIVE_CHANNELS)-1:0] channel;
		logic completes;
	} tagInfo_t;
	
	tagInfo_t tagMemory [TAG_COUNT-1:0];
	
	trailingZeros #(
		.WIDTH(TAG_COUNT)
	) nextTagDetector (
		.vector       (tagAvailable_reg),
		.trailingCount(nextTag)
	);
	
	always_comb begin : tagManager
		tagAvailable_comb = (tagAvailable_reg | makeTagAvailable_0 | makeTagAvailable_1 ) & ~useTag;
		
		nextTagMask           = tagAvailable_reg & ~(tagAvailable_reg-1); //Extract trailing one
	end
	
	always_ff @(posedge clk) begin : tagMemoryUpdater
		if(updateTagMemory) begin
			tagMemory[nextTag].channel     <= link.channelReceive; //FIXME: move to register process
			tagMemory[nextTag].completes   <= link.finalizeReceiveCommand;
		end
		
		tagAvailableFlag_reg <= | (tagAvailable_reg & (tagAvailable_reg-1)); //Simplification of  |(tagAvailable_reg & ~ nextTagMask)
	end

	//== Receiver ======
	//--- States -----------
	typedef enum logic [1:0] {RECEIVE_CRUSING, RECEIVE_FIX_REMAINDER, RECEIVE_FIX_SECONDHEADER, RECEIVE_FIX_REMAINDER_AND_SECONDHEADER} receiverState_t;
	receiverState_t receiverState_reg;
	receiverState_t receiverState_comb;

	pcieHeaders::requesterCompletion completionHeader [1:0];
	pcieHeaders::requesterCompletion bufferedHeader;
	
	logic [pcieInterfaces::INTERFACEWIDTH-1:0] requestBuffer_comb;
	logic [pcieInterfaces::INTERFACEWIDTH-1:0] requestBuffer_reg;
	
	logic [pcieInterfaces::BYTEENABLEBITS-1:0] byteEnableBuffer_comb;
	logic [pcieInterfaces::BYTEENABLEBITS-1:0] byteEnableBuffer_reg;
	
	logic [$clog2(pcie::MAX_PAYLOAD_BYTES)-1:0] requestRemainder_comb;
	logic [$clog2(pcie::MAX_PAYLOAD_BYTES)-1:0] requestRemainder_reg;
	
	logic [$clog2(pcieInterfaces::INTERFACEWIDTH/pcie::DWORDBITS)-1:0] receiveShift_comb;
	logic [$clog2(pcieInterfaces::INTERFACEWIDTH/pcie::DWORDBITS)-1:0] receiveShift_reg;
	
	logic [pcieInterfaces::TAG_BITS-1:0] tagReceiving_comb;
	logic [pcieInterfaces::TAG_BITS-1:0] tagReceiving_reg;
	
	logic isLastPacket_comb;
	logic isLastPacket_reg;
	
	//logic overflow_frontHalf_FAST;
	logic overflow_backHalf_FAST;
	
	logic [$clog2(pcieInterfaces::DWORDS)-1:0] lastBytes_comb;
	logic [$clog2(pcieInterfaces::DWORDS)-1:0] lastBytes_reg;
	
	logic [$clog2(pcieInterfaces::DWORDS):0] overflowIntermediate; //we need one extra bit

	logic receiveCompletion_comb;
	logic receiveCompletion_reg;

	// START RANDOM SHIT ===============================
	assign flowcontrol.informationSelect = flowcontrol.TRANSMITAVAILABLE;
	// END RANDOM SHIT ==================================

	// === REGISTERS ============================

	always_ff @(posedge clk) begin : register
		if(reset) begin
			dispatcherState_reg = DISPATCH_IDLE;

			tagAvailable_reg    = '1;
			
			//== INTERRUPT ENGINE ==
			interruptEngineState_reg         <= INTERRUPT_ENGINE_IDLE;
			interruptPendingPhysicalFunction0_reg <= 0;
			
			interrupt_request_reg            <= 0;
			
			//receiver
			byteEnableBuffer_reg             <= '0;
			
			requestRemainder_reg             <= 0;
			receiverState_reg                <= RECEIVE_CRUSING;
			
			sendCompletion_reg               <= 0;
			receiveCompletion_reg            <= 0;
		end else begin
			dispatcherState_reg              <= dispatcherState_comb;

			tagAvailable_reg                 <= tagAvailable_comb;

			//== INTERRUPT ENGINE ==
			interruptEngineState_reg         <= interruptEngineState_comb;
			interruptPendingPhysicalFunction0_reg <= interrupt.pending_status.physicalFunction0;
			
			interrupt_request_reg            <= interrupt_request_comb || link.interruptRequests;
			
			//receiver
			byteEnableBuffer_reg             <= byteEnableBuffer_comb;
			
			receiverState_reg                <= receiverState_comb;
			requestRemainder_reg             <= requestRemainder_comb;
			
			sendCompletion_reg               <= sendCompletion_comb;
			receiveCompletion_reg            <= receiveCompletion_comb;
		end

		dataAlign_reg         <= dataAlign_comb;
		sentDWCounter_reg     <= sentDWCounter_comb;
		sentDWCounterPreDecrement_reg <= sentDWCounterPreDecrement_comb;
		request_reg           <= request_comb;
		
		requestBuffer_reg     <= requestBuffer_comb;
		receiveShift_reg      <= receiveShift_comb;
		
		tagReceiving_reg      <= tagReceiving_comb;
		
		isLastPacket_reg      <= isLastPacket_comb;
		
		lastBytes_reg         <= lastBytes_comb;
		
		sendChannel_reg       <= sendChannel_comb;
	end

	// === DISPATCHER ============================

	//static requesterRequest sideband signals
	assign requesterRequest.user.byteEnable_first       = 4'hf;
	assign requesterRequest.user.byteEnable_last        = 4'hf;
	assign requesterRequest.user.offset                 = '0;
	assign requesterRequest.user.parity                 = '0;
	assign requesterRequest.user.discontinue            = 0;
	assign requesterRequest.user.tph_present            = 0;
	assign requesterRequest.user.tph_type               = 0;
	assign requesterRequest.user.tph_indirectTag_enable = 0;
	assign requesterRequest.user.tph_steeringTag        = 0;
	assign requesterRequest.user.sequenceNumber         = 0;
	assign requesterRequest.user.parity                 = '0;
	
	assign link.completedSendCommand = sendCompletion_reg.completed;

	always_comb begin : dispatcher	
		logic canReceive = link.validReceiveCommand && tagAvailableFlag_reg;
		
		sentDWCounter_comb      = sentDWCounter_reg;
		sentDWCounterPreDecrement_comb = sentDWCounterPreDecrement_reg;
		
		dispatcherState_comb    = dispatcherState_reg;
		
		dataAlign_comb          = dataAlign_reg;

		request_comb            = request_reg;

		sendChannel_comb        = sendChannel_reg;

		link.nextSendData       = 0;
		link.nextSendCommand    = 0;
		link.sourceChannel      = sendChannel_reg;

		//link.nextReceiveCommand = 0;
		link.nextReceiveCommand = link.validReceiveCommand && tagAvailableFlag_reg && (requesterRequest.ready || dispatcherState_reg != DISPATCH_FINALIZE);

		requesterRequest.data   = request_reg;
	
		useTag                  = '0;
		updateTagMemory         = 0;

		sendCompletion_comb.finalize  = sendCompletion_reg.finalize;
		sendCompletion_comb.completed = 0;
			
		unique case(dispatcherState_reg)
			DISPATCH_IDLE, DISPATCH_FINALIZE : begin
				if(requesterRequest.ready) begin
					if(sendCompletion_reg.finalize) begin
						sendCompletion_comb.completed = 1;
						sendCompletion_comb.finalize  = 0; //Done on next start anyway
					end
					
					dispatcherState_comb              = DISPATCH_IDLE;
				end
						
				//FIXME: does dispatcherState_reg matter?
				if(requesterRequest.ready || dispatcherState_reg != DISPATCH_FINALIZE) begin
					//dispatch
					if(canReceive) begin
						automatic pcieHeaders::requesterRequestMemory header = pcieHeaders::init_requesterRequestMemory();
										
						header.headerType               = pcieHeaders::MEM_READ;
						header.address                  = link.addressReceive[$left(link.addressReceive):2];
						header.dWordCount               = link.sizeReceive[$bits(header.dWordCount)+1:2];
						header.tag                      = nextTag;
									
						useTag                          = nextTagMask;
						updateTagMemory                 = 1;
										
						//link.nextReceiveCommand         = 1;
		
						request_comb[$bits(header)-1:0] = header;
						
						requesterRequest.data           = request_comb;
						
						sentDWCounter_comb              = $bits(pcieHeaders::requesterRequestMemory)/pcie::DWORDBITS; //Won't work for interfaces smaller than the header
						//sentDWCounterPreDecrement_comb  = sentDWCounter_comb - pcieInterfaces::DWORDS;
						//requesterRequest.keep           = 8'b00001111;//After noticing that a = b - b; and a =0; get significatn different timings, I do not trust the XILINX constant folding. So we do this by hand: '1 >> (pcieInterfaces::DWORDS - sentDWCounter_comb[$clog2(pcieInterfaces::DWORDS)-1:0]);

						dispatcherState_comb           = DISPATCH_FINALIZE;
					end else if(link.validSendCommand) begin //TODO decide what has prio, send or receive
						automatic pcieHeaders::requesterRequestMemory header = pcieHeaders::init_requesterRequestMemory();
						//we send something
						//setup header and first data
						header.headerType              = pcieHeaders::MEM_WRITE;
						header.address                 = link.addressSend[$left(link.addressSend):2];
						header.dWordCount              = link.sizeSend[$bits(header.dWordCount)+1:2]; //TODO: byte granular transfer sizes? i.e. round up
						
						sentDWCounter_comb             = header.dWordCount + $bits(pcieHeaders::requesterRequestMemory)/pcie::DWORDBITS;
						sentDWCounterPreDecrement_comb = header.dWordCount + $bits(pcieHeaders::requesterRequestMemory)/pcie::DWORDBITS - pcieInterfaces::DWORDS;
		
						dataAlign_comb                 = link.dataSend[255:128];
						request_comb                   = {link.dataSend[127:0], header};
		
						sendCompletion_comb.finalize   = link.finalizeSendCommand;

						requesterRequest.data          = request_comb;
		
						sendChannel_comb               = link.nextSourceChannel;
						
						link.sourceChannel             = link.nextSourceChannel;
						link.nextSendData              = 1;
						link.nextSendCommand           = 1;
		
						if(header.dWordCount < pcieInterfaces::DWORDS - $bits(pcieHeaders::requesterRequestMemory)) begin
							//requesterRequest.keep      = '1 >> (pcieInterfaces::DWORDS - sentDWCounter_comb[$clog2(pcieInterfaces::DWORDS)-1:0]);
							dispatcherState_comb       = DISPATCH_FINALIZE;
						end else begin
							//requesterRequest.keep      = '1;
							dispatcherState_comb       = DISPATCH_SEND;
						end
					end
				end
			end
			DISPATCH_SEND: begin
				if(requesterRequest.ready) begin
					dataAlign_comb                   = link.dataSend[255:128];
					request_comb                     = {link.dataSend[127:0], dataAlign_reg};

					//TODO: actually account for data consumed.
					sentDWCounter_comb               = sentDWCounterPreDecrement_reg;
					sentDWCounterPreDecrement_comb   = sentDWCounterPreDecrement_reg - pcieInterfaces::DWORDS;

					requesterRequest.data            = request_comb;
					link.nextSendData                = 1;

					//TODO: restart on error
					//TODO: non DWORD aligned starting offsets

					if(sentDWCounter_reg < 2*pcieInterfaces::DWORDS) begin
						//requesterRequest.keep      = '1 >> (pcieInterfaces::DWORDS - sentDWCounter_comb[$clog2(pcieInterfaces::DWORDS)-1:0]);
						dispatcherState_comb             = DISPATCH_FINALIZE;
					end
				end
			end
		endcase
		
		requesterRequest.valid      = dispatcherState_comb != DISPATCH_IDLE;
		requesterRequest.last       = dispatcherState_comb == DISPATCH_FINALIZE;
		
		unique case(sentDWCounter_comb)
			0:
				requesterRequest.keep = 0'b00000000;
			1:
				requesterRequest.keep = 0'b00000001;
			2:
				requesterRequest.keep = 0'b00000011;
			3:
				requesterRequest.keep = 0'b00000111;
			4:
				requesterRequest.keep = 0'b00001111;
			5:
				requesterRequest.keep = 0'b00011111;
			6:
				requesterRequest.keep = 0'b00111111;
			7:
				requesterRequest.keep = 0'b01111111;
			default:
				requesterRequest.keep = '1;
		endcase
		
		/*if(sentDWCounter_comb < pcieInterfaces::DWORDS) begin
			requesterRequest.keep   = '1 >> (pcieInterfaces::DWORDS - sentDWCounter_comb[$clog2(pcieInterfaces::DWORDS)-1:0]);
		end else begin
			requesterRequest.keep   = '1;
		end*/
	end
	
	// === RECEIVER ============================

	assign completionHeader[0] = requesterCompletion.data[$bits(pcieHeaders::requesterCompletion)-1:0];
	assign completionHeader[1] = requesterCompletion.data[$bits(pcieHeaders::requesterCompletion)-1+128:0+128]; //NOTE: Assuming 256 bit interface, by the time we take a look at the second header the data arrived in the buffer
	assign bufferedHeader      = requestBuffer_reg[$bits(pcieHeaders::requesterCompletion)-1+128:0+128];
	
	rotatorConnect #(
		.INPUTWIDTH        (pcieInterfaces::INTERFACEWIDTH),
		.SHIFTBITS_PER_STEP(pcie::DWORDBITS)
	) receiveAligner ();
	
	barrelShifterRight #(
		.INPUTWIDTH        (pcieInterfaces::INTERFACEWIDTH),
		.SHIFTBITS_PER_STEP(pcie::DWORDBITS)
	)
	receiveAlignerCore (
		.clk(clk),
		.link(receiveAligner)
	);
	
	logic [pcieInterfaces::DWORDS-1:0] sourceMask;
	//logic [pcieInterfaces::DWORDS-1:0] sourceMask_DEBUG;
	//(* mark_debug = "true" *) logic [pcieInterfaces::INTERFACEWIDTH-1:0] dataComb_DEBUG;
	
	assign sourceMask = {pcieInterfaces::DWORDS{1'b1}} << receiveAligner.rotationRight;
	
	for(genvar i=0; i < pcieInterfaces::DWORDS; i++) begin : receiveDataMux
		always_comb begin
			if(!sourceMask[i]) begin
				receiveAligner.dataIn[pcie::DWORDBITS*(i+1)-1:i*pcie::DWORDBITS] = requesterCompletion.data[pcie::DWORDBITS*(i+1)-1:i*pcie::DWORDBITS];
			end else begin
				receiveAligner.dataIn[pcie::DWORDBITS*(i+1)-1:i*pcie::DWORDBITS] = requestBuffer_reg[pcie::DWORDBITS*(i+1)-1:i*pcie::DWORDBITS];
			end
		end
	end
	
	rotatorConnect #(
		.INPUTWIDTH        (pcieInterfaces::BYTEENABLEBITS),
		.SHIFTBITS_PER_STEP(pcie::DWORDBITS/pcieInterfaces::BYTEBITS)
	) byteEnableAligner ();
	
	barrelShifterRight #(
		.INPUTWIDTH        (pcieInterfaces::BYTEENABLEBITS),
		.SHIFTBITS_PER_STEP(pcie::DWORDBITS/pcieInterfaces::BYTEBITS)
	)
	byteEnableAlignerCore (
		.clk(clk),
		.link(byteEnableAligner)
	);
	
	assign byteEnableAligner.rotationRight = receiveAligner.rotationRight;
	
	localparam BYTES_PER_DWORD = pcie::DWORDBITS / pcieInterfaces::BYTEBITS;
	
	for(genvar i=0; i < pcieInterfaces::DWORDS; ++i) begin : receiveByteEnableMux
		always_comb begin
			if(!sourceMask[i]) begin
				//force the inputs to zero in case we are not activly receiving new data from the interface
				//mask the last DW byte enables in case we have two headers
				if(
					receiverState_reg == RECEIVE_CRUSING && (
						i != pcieInterfaces::DWORDS-1 || 
						requesterCompletion.user.byteEnable[SECOND_HEADER_DW_OFFSET*BYTES_PER_DWORD]
					)
				) begin
					byteEnableAligner.dataIn[BYTES_PER_DWORD*(i+1)-1:BYTES_PER_DWORD*i] = requesterCompletion.user.byteEnable[BYTES_PER_DWORD*(i+1)-1:BYTES_PER_DWORD*i];
				end else begin
					byteEnableAligner.dataIn[BYTES_PER_DWORD*(i+1)-1:BYTES_PER_DWORD*i] = '0;
				end
			end else begin
				//suppress the buffer byte enables for the last dw in case we are dealing with a header in the back half and an overflow in the front
				if(i != pcieInterfaces::DWORDS-1 || receiverState_reg != RECEIVE_FIX_REMAINDER_AND_SECONDHEADER) begin
					byteEnableAligner.dataIn[BYTES_PER_DWORD*(i+1)-1:BYTES_PER_DWORD*i] = byteEnableBuffer_reg[BYTES_PER_DWORD*(i+1)-1:BYTES_PER_DWORD*i];
				end else begin
					byteEnableAligner.dataIn[BYTES_PER_DWORD*(i+1)-1:BYTES_PER_DWORD*i] = '0;
				end
			end
		end
	end
	
	/*always_ff @(posedge clk) begin :debug
		if(reset) begin
			sourceMask_DEBUG = '0;
			dataComb_DEBUG = '0;
		end else begin
			sourceMask_DEBUG = sourceMask;
			dataComb_DEBUG = receiveAligner.dataIn;
		end
	end*/
	
	/* OLD overflow calculation
	logic overflow_frontHalf;
	logic overflow_backHalf;
	
	always_comb begin : overflowCalculation
		overflow_frontHalf = 0;
		
		for(int i = 0; i < pcieInterfaces::DWORDS/2; i++) begin
			overflow_frontHalf |= requesterCompletion.user.byteEnable[(i+1)*pcie::DWORDBITS/8-1] & ~sourceMask[i];
		end
		
		overflow_backHalf = 0;
		
		for(int i = pcieInterfaces::DWORDS/2; i < pcieInterfaces::DWORDS; i++) begin
			overflow_backHalf |= requesterCompletion.user.byteEnable[(i+1)*pcie::DWORDBITS/8-1] & ~sourceMask[i];
		end
	end
	*/
	
	// BEGIN TIMING FIX
	typedef struct packed {
		logic [pcieInterfaces::INTERFACEWIDTH-1:0] data;
		logic [pcieInterfaces::BYTEENABLEBITS-1:0]            valid;
		logic                                      write;
		logic [$clog2(RECEIVE_CHANNELS)-1:0]       channel;		
	} dataOutVector_t;
	
	dataOutVector_t dataOutVector;
	dataOutVector_t dataOutVectorDelayed;
	
	pipeline #(
		.WIDTH ($bits(dataOutVector_t)),
		.STAGES(1),
		.RESET (1)
	)
	u_pipeline (
		.clk    (clk),
		.reset  (reset),
		.dataIn (dataOutVector),
		.dataOut(dataOutVectorDelayed)
	);
	
	assign dataOutVector.data      = receiveAligner.dataOut;
		
	assign link.dataReceive        = dataOutVectorDelayed.data;
	assign link.validReceiveData   = dataOutVectorDelayed.valid;
	assign link.write              = dataOutVectorDelayed.write;
	assign link.channelDestination = dataOutVectorDelayed.channel;
	//END TIMING FIX
	
	assign link.completedReceiveCommand = receiveCompletion_reg;
	
	always_comb begin : receiver
		requesterCompletion.ready    = 1;
		
		makeTagAvailable_0           = '0;
		makeTagAvailable_1           = '0;
	                                 
		requestBuffer_comb           = requestBuffer_reg;
		byteEnableBuffer_comb        = byteEnableBuffer_reg;
		receiveShift_comb            = receiveShift_reg;
		requestRemainder_comb        = requestRemainder_reg;
		                             
		tagReceiving_comb            = tagReceiving_reg;
		                             
		dataOutVector.channel        = tagMemory[tagReceiving_reg].channel;
		//dataOutVector.valid        = requesterCompletion.valid; //TODO: use tag available reg as a sanity check? (i.e. !tagAvailable_reg[tagReceiving_reg]) DOWNSIDE: can only free tag at end of transfer)
		dataOutVector.write          = requesterCompletion.valid;
		                             
		receiverState_comb           = receiverState_reg;
		
		receiveAligner.rotationRight = receiveShift_reg;
	
		isLastPacket_comb            = isLastPacket_reg;
		                             
		lastBytes_comb               = lastBytes_reg;
		                             
		overflowIntermediate         = lastBytes_reg + receiveShift_reg;
		
		//overflow_frontHalf_FAST    = overflowIntermediate[$clog2(pcieInterfaces::DWORDS - SECOND_HEADER_DW_OFFSET)];
		overflow_backHalf_FAST       = overflowIntermediate[$clog2(pcieInterfaces::DWORDS)];
		                             
		receiveCompletion_comb       = 0;
	
		unique case(receiverState_reg)
			RECEIVE_CRUSING : begin
				if(requesterCompletion.valid) begin
					requestBuffer_comb    = requesterCompletion.data;
					byteEnableBuffer_comb = requesterCompletion.user.byteEnable;
					
					if(requesterCompletion.user.startOfFrame_0) begin
						if(requesterCompletion.user.byteEnable[0]) begin
						//Header in second half only
							if(overflow_backHalf_FAST) begin //FIXME is this borken
								requesterCompletion.ready = 0;
								receiverState_comb = RECEIVE_FIX_REMAINDER_AND_SECONDHEADER;
							end else begin
								tagReceiving_comb = completionHeader[1].tag[pcieInterfaces::TAG_BITS-1:0];
								//receiveShift_comb = completionHeader[1].address[5:2] - HEADER_DWS; // [5:2] clip the bits for the DWord alignment over the interface from the byte address, -3: account for the start offset
								receiveShift_comb = completionHeader[1].address[4:2] ^ 3'b011; //optimized form of (HEADER_DWS-completionHeader[1].address[5:2])%8 = (3 - address[5:2])%8 = (4 + ~address[5:2])%8;
								byteEnableBuffer_comb[pcieInterfaces::BYTEENABLEBITS/2-1:0] = '0;
								
								if(isLastPacket_reg) begin
									receiveCompletion_comb = 1;
									isLastPacket_comb = 0;
								end
								
								if(completionHeader[1].address[4:2] == 3'b111 || requesterCompletion.user.endOfFrame_1.isEnd) begin //If we have just one byte we need an extra output cycle as well
									//the data would be aligned and warrent immediate output
									requesterCompletion.ready = 0;
									receiverState_comb        = RECEIVE_FIX_SECONDHEADER;
								end else begin
									lastBytes_comb    = completionHeader[1].dWordCount + HEADER_DWS + SECOND_HEADER_DW_OFFSET;									
									isLastPacket_comb = tagMemory[tagReceiving_comb].completes && completionHeader[1].requestCompleted;

									if(completionHeader[1].requestCompleted) begin
										makeTagAvailable_0[tagReceiving_comb] = 1;
									end
									
									//TODO: set error flag: if(completionHeader[1].errorCode != pcieHeaders::RC_ERROR_NONE) begin									end
								end
							end
						end else begin
						//Header in first half
							//We only need thi if the frame ends in the same beat => dWordCount <= 5
							automatic logic [3:0] dataEnd = completionHeader[0].dWordCount[2:0] + completionHeader[0].address[4:2];
							automatic logic overflowBack  = dataEnd[3];
						
							tagReceiving_comb = completionHeader[0].tag[pcieInterfaces::TAG_BITS-1:0];
							//receiveShift_comb = completionHeader[0].address[5:2] - HEADER_DWS; // [5:2] clip the bits for the DWord alignment over the interface from the byte address, -3: account for the start offset
							receiveShift_comb = completionHeader[0].address[4:2] ^ 3'b011;
							
							lastBytes_comb = completionHeader[0].dWordCount + HEADER_DWS;
							
							receiveAligner.rotationRight = receiveShift_comb;
							dataOutVector.channel        = tagMemory[tagReceiving_comb].channel;
													
							if(requesterCompletion.user.endOfFrame_0 && (!overflowBack || requesterCompletion.user.startOfFrame_1)) begin
								byteEnableBuffer_comb[pcieInterfaces::BYTEENABLEBITS/2-1:0] = '0;
							end
							
							if(requesterCompletion.user.endOfFrame_0 && !requesterCompletion.user.startOfFrame_1 && !overflowBack) begin
								byteEnableBuffer_comb[pcieInterfaces::BYTEENABLEBITS-1:pcieInterfaces::BYTEENABLEBITS/2] = '0;
							end
							
							if(requesterCompletion.user.endOfFrame_0.isEnd) begin
								if (overflowBack) begin //We can consider the second half, should there be a second header, we undo this, see below.
									requesterCompletion.ready = 0;
									receiverState_comb = RECEIVE_FIX_REMAINDER;
								end
								
								if(tagMemory[tagReceiving_comb].completes && completionHeader[0].requestCompleted) begin
									if((requesterCompletion.user.startOfFrame_1 && !(completionHeader[0].dWordCount > pcieInterfaces::DWORDS - HEADER_DWS - SECOND_HEADER_DW_OFFSET)) || !(completionHeader[0].dWordCount > pcieInterfaces::DWORDS - HEADER_DWS)) begin
										receiveCompletion_comb = 1;
									end else begin
										isLastPacket_comb = 1;
									end
								end
							end else begin
								if(completionHeader[0].address[4:2] < HEADER_DWS) begin
									dataOutVector.write = 0; //we need the next line before starting output
								end							
							end
							
							if(completionHeader[0].requestCompleted) begin
								makeTagAvailable_0[tagReceiving_comb] = 1;
							end
							
							if(!requesterCompletion.user.endOfFrame_0.isEnd && tagMemory[tagReceiving_comb].completes && completionHeader[0].requestCompleted) begin
								isLastPacket_comb = 1;
							end
							
							if(requesterCompletion.user.startOfFrame_1) begin
							//Two headers
								requesterCompletion.ready = 0;
								
								tagReceiving_comb = completionHeader[1].tag[pcieInterfaces::TAG_BITS-1:0];
								//receiveShift_comb = bufferedHeader.address[5:2] - HEADER_DWS;
								receiveShift_comb = bufferedHeader.address[4:2] ^ 3'b111; //7-address%8 optimized
									
								receiverState_comb = RECEIVE_FIX_SECONDHEADER;
							end
							
							//TODO: set error flag: if(completionHeader[1].errorCode != pcieHeaders::RC_ERROR_NONE) begin									end
						end
					end else begin
					//pure data
						if(requesterCompletion.user.endOfFrame_0.isEnd && overflow_backHalf_FAST) begin
							requesterCompletion.ready = 0;
							receiverState_comb        = RECEIVE_FIX_REMAINDER;
						end
						
						if(requesterCompletion.user.endOfFrame_0.isEnd && !overflow_backHalf_FAST) begin
							byteEnableBuffer_comb     = '0;
						end
						
						if(requesterCompletion.user.endOfFrame_0.isEnd && !overflow_backHalf_FAST && isLastPacket_reg) begin
							isLastPacket_comb      = 0;
							receiveCompletion_comb = 1;
						end
					end
				end else begin
					dataOutVector.write = 0; //this case should be handled by the default valid above TODO remove
				end
			end
			RECEIVE_FIX_REMAINDER : begin
				//This pumps out another cycle, the data has moved into the request buffer, thus the remainder is now automatically output from there, we do not mask any invalid bytes though
				if(isLastPacket_reg) begin
					isLastPacket_comb = 0;
					receiveCompletion_comb = 1;
				end
				
				byteEnableBuffer_comb = '0;
				dataOutVector.write   = 1;
				
				receiverState_comb    = RECEIVE_CRUSING;
			end
			RECEIVE_FIX_SECONDHEADER : begin
				//here we always require immediate output (other cases are handled inline), thus no need to supress valid signal EXCEPT coming from the two header case so we do check	
				dataOutVector.channel = tagMemory[tagReceiving_reg].channel;
				
				lastBytes_comb    = bufferedHeader.dWordCount + HEADER_DWS + SECOND_HEADER_DW_OFFSET;
				
				if(bufferedHeader.address[4:2] != 3'b111) begin 
					//suppress output if we can't output just yet
					dataOutVector.write = 0;
				end
				
				if(bufferedHeader.dWordCount[$left(bufferedHeader.dWordCount):$right(bufferedHeader.dWordCount)+1]==0) begin
					//We have a packet that ends in this beat.
					
					//since we have already copied the data to the buffer we can do the aligning by just generating the output (we will have the data on the interface AND in the buffer, since this is one cycle past the arival of the data
					//Thus it is the correct thing to just output if there is no more data coming for the packet
					dataOutVector.write = 1;
				end
				
				if(bufferedHeader.requestCompleted) begin
					makeTagAvailable_1[tagReceiving_reg] = 1;
					byteEnableBuffer_comb                = '0;
					
					if(tagMemory[tagReceiving_reg].completes) begin
						if(bufferedHeader.dWordCount[$left(bufferedHeader.dWordCount):$right(bufferedHeader.dWordCount)+1]==0) begin
							receiveCompletion_comb = 1;
						end else begin
							isLastPacket_comb = 1;
						end
					end
				end
				
				receiverState_comb = RECEIVE_CRUSING;
			end
			RECEIVE_FIX_REMAINDER_AND_SECONDHEADER : begin
				//receiveShift_comb = bufferedHeader.address[5:2] - HEADER_DWS;
				//TODO: is buffered header still valid when we get to the handling of it? (we got through this state and only after do we enter RECEIVE_FIX_SECONDHEADER
				receiveShift_comb   = bufferedHeader.address[4:2] ^ 3'b111; //(7 - address%8)%8 optimized
				tagReceiving_comb   = bufferedHeader.tag[pcieInterfaces::TAG_BITS-1:0];
				
				dataOutVector.write = 1;
				
				byteEnableBuffer_comb[pcieInterfaces::BYTEENABLEBITS/2-1:0] = '0;
				
				if(isLastPacket_reg) begin
					receiveCompletion_comb = 1;
					isLastPacket_comb = 0;
				end
				
				if(bufferedHeader.address[4:2] != 3'b111 && bufferedHeader.dWordCount[$left(bufferedHeader.dWordCount):$right(bufferedHeader.dWordCount)+1]!=0) begin //if we have a short second header we have extra work				
					if(bufferedHeader.requestCompleted) begin
						makeTagAvailable_1[tagReceiving_comb] = 1;
						
						isLastPacket_comb = tagMemory[tagReceiving_comb].completes;
					end
				
					receiverState_comb = RECEIVE_CRUSING;
				end else begin			
					requesterCompletion.ready = 0;
					receiverState_comb = RECEIVE_FIX_SECONDHEADER;
				end
			end
			default: begin
			end
		endcase
		
		dataOutVector.valid          = byteEnableAligner.dataOut & {pcieInterfaces::BYTEENABLEBITS{dataOutVector.write}};
	end
	
	// === INTERRUPT ENGINE ============================
	
	assign interrupt.attr = 0;
	assign interrupt.tph_present = 0;
	assign interrupt.tph_type = 0;
	assign interrupt.tph_st_tag = 0;
	assign interrupt.function_number = 0;
	assign interrupt.select = '0;
	
	assign interrupt.legacy_pending      = 2'b00;
	assign interrupt.legacy_interrupt    = 4'b0000;
	
	always_comb begin : irq_engine
		interrupt.pending_status.physicalFunction1 = '0;
		interrupt.pending_status.physicalFunction0 = '0;//interruptPendingPhysicalFunction0_reg;
		
		interrupt.interruptVector = '0;
		
		interrupt_request_fired = interrupt_request_reg & ~(interrupt_request_reg - 1);
		interrupt_request_comb  = interrupt_request_reg;
		
		interruptEngineState_comb = interruptEngineState_reg;
		
		unique case(interruptEngineState_reg)
			INTERRUPT_ENGINE_IDLE : begin
				if(interrupt_request_reg) begin
					interrupt_request_comb = interrupt_request_reg & ~interrupt_request_fired;
					
					interrupt.interruptVector = interrupt_request_fired;
					//interrupt.pending_status.physicalFunction0 = 1 << 0; //set to the same value as interruptVector. THIS BREAKS IT!
					
					interruptEngineState_comb = INTERRUPT_ENGINE_WAITING;
				end
			end
			INTERRUPT_ENGINE_WAITING : begin
				if(interrupt.sent) begin	
					if(interrupt_request_reg) begin
						interrupt_request_comb = interrupt_request_reg & ~interrupt_request_fired;
						interrupt.interruptVector = interrupt_request_fired;
					end else begin
						interruptEngineState_comb = INTERRUPT_ENGINE_IDLE;
					end
				end
				
				if(interrupt.fail) begin
					//TODO: this is silly, we just retry till we die
				end
			end
		endcase
	end

endmodule
