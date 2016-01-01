import hardcoreConfig::*;
import pcie::*;
import pcieInterfaces::*;
import utility::max;

module arbiter # (
	parameter int unsigned CHANNELS          = 2,
	parameter hardcoreConfig::channelMode_t [0:CHANNELS-1] CHANNEL_MODES = '{default: hardcoreConfig::CM_NOT_PRESENT},
	parameter int unsigned DATAWIDTH         = pcieInterfaces::INTERFACEWIDTH,
	parameter int unsigned BYTEWIDTH         = pcieInterfaces::BYTEBITS,
	parameter int unsigned REGISTERWIDTH     = 32,
	parameter int unsigned ADDRESSWIDTH      = 64,
	parameter int unsigned SEND_CHANNELS     = hardcoreConfig::channelInfoParser #(CHANNELS)::channelModeCount(CHANNEL_MODES, hardcoreConfig::CM_READ_ONLY),
	parameter int unsigned RECEIVE_CHANNELS  = hardcoreConfig::channelInfoParser #(CHANNELS)::channelModeCount(CHANNEL_MODES, hardcoreConfig::CM_WRITE_ONLY)
)(
	input logic clk,
	input logic reset,

	/*registerfileConnector #(
		.CHANNELS(CHANNELS)
	) registerfile,*/
	registerfileConnector.arbiter registerfile,
	
	requestEngineConnect #(
		.DATAWIDTH    (DATAWIDTH),
		.REGISTERWIDTH(REGISTERWIDTH),
		.ADDRESSWIDTH (ADDRESSWIDTH)
	) requestEngine,

	Adapter2Arbiter_send.arbiter sendLink[SEND_CHANNELS-1:0],
	Adapter2Arbiter_receive.arbiter receiveLink[RECEIVE_CHANNELS-1:0],
	
	pcie_configurationStatus.userLogic configurationStatus,
	
	input logic debugButton
);

localparam int unsigned BYTES = DATAWIDTH/BYTEWIDTH;
localparam int unsigned MAX_RESERVE_BITS = $clog2(8192 + 1); //FIXME: get this dynamically form the usermodule

typedef logic [$clog2(pcie::XILINX_MAX_PAYLOAD_SIZE+1)-1:0] transferSendSize_t;
typedef logic [$clog2(pcie::XILINX_MAX_REQUEST_SIZE+1)-1:0] transferReceiveSize_t;
	
typedef logic [$clog2(pcie::XILINX_MAX_PAYLOAD_SIZE/pcieInterfaces::INTERFACEBYTES + pcie::XILINX_MAX_PAYLOAD_SIZE%pcieInterfaces::INTERFACEBYTES + 1)-1:0] transferSendBeats_t;
typedef logic [$clog2(pcie::XILINX_MAX_REQUEST_SIZE/pcieInterfaces::INTERFACEBYTES + pcie::XILINX_MAX_REQUEST_SIZE%pcieInterfaces::INTERFACEBYTES + 1)-1:0] transferReceiveBeats_t;

function transferSendBeats_t transferSendBeats(transferSendSize_t bytes);
	//return bytes[$left(bytes):$clog2(pcieInterfaces::INTERFACEBYTES)] + (bytes[$clog2(pcieInterfaces::INTERFACEBYTES)-1:0] > 0);
	return bytes[$left(bytes):$clog2(pcieInterfaces::INTERFACEBYTES)] + (| bytes[$clog2(pcieInterfaces::INTERFACEBYTES)-1:0]);
	//return transferReceiveBeats(bytes);
endfunction

function transferReceiveBeats_t transferReceiveBeats(transferReceiveSize_t bytes);
	return bytes[$left(bytes):$clog2(pcieInterfaces::INTERFACEBYTES)] + (bytes[$clog2(pcieInterfaces::INTERFACEBYTES)-1:0] > 0);
endfunction

//FIXME
logic [$clog2(pcie::XILINX_MAX_PAYLOAD_SIZE+1)-1:0] maxPayloadSize = 256;// << configurationStatus.maxPayloadSize; //WHAT i'd like to do configurationStatus.payloadSizeToInt(configurationStatus.maxPayloadSize);
logic [$clog2(pcie::XILINX_MAX_REQUEST_SIZE+1)-1:0] maxRequestSize = 512;// << configurationStatus.maxReadRequestSize; //WHAT i'd like to do configurationStatus.requestSizeToInt(configurationStatus.maxReadRequestSize);

typedef struct packed {
	logic [ADDRESSWIDTH-1:0]  address;
	logic [REGISTERWIDTH-1:0] size; //DOES NOT WORK: $left(registerfile.commandSize[0])   :$right(registerfile.commandSize[0])
	logic                     valid;	
} commandInfo_t;

//commandInfo_t send[SEND_CHANNELS-1:0];
logic         [SEND_CHANNELS-1:0] sendValid;
logic         [SEND_CHANNELS-1:0] sendValid_reg;

//commandInfo_t receive[RECEIVE_CHANNELS-1:0];
logic         [RECEIVE_CHANNELS-1:0] receiveValid;


//FIXME: replace this with the arbitrationPipeline
typedef struct {
	//logic [REGISTERWIDTH-1:0] size;
	logic [max($clog2(SEND_CHANNELS)-1, 0):0] channelId;
} arbitrationResult_send_t;

typedef struct packed {
	//logic [REGISTERWIDTH-1:0] size;
	logic [max($clog2(RECEIVE_CHANNELS)-1, 0):0] channelId;
} arbitrationResult_receive_t;
	
logic nextSendCommand;
logic nextSendCommand_reg;
logic nextReceiveCommand;

arbitrationResult_send_t    arbitrationSend;
arbitrationResult_send_t    arbitrationSend_reg;
arbitrationResult_receive_t arbitrationReceive;
arbitrationResult_receive_t arbitrationReceive_reg;

//=== Pipeline [Decoupling of arbitration] =====
//Cost: we commit to one transaction and can't revert that decision. Gain: Timing gets a lot easier.
typedef struct packed {
	logic [$clog2(pcie::XILINX_MAX_PAYLOAD_SIZE+1)-1:0] sizeSend; //we actually need 0
	logic [ADDRESSWIDTH-1:0]  addressSend;
	logic                     validSendCommand;
	logic                     finalizeSendCommand;
	logic [$clog2(SEND_CHANNELS)-1:0] nextSourceChannel;
	
	logic [$clog2(pcie::XILINX_MAX_REQUEST_SIZE+1)-1:0] sizeReceive; //we actually need 0
	logic [ADDRESSWIDTH-1:0]  addressReceive;
	logic [$clog2(RECEIVE_CHANNELS)-1:0] channelReceive;
	
	logic                     validReceiveCommand;
	logic                     finalizeReceiveCommand;
} arbitrationPipeline_t;

(* mark_debug = "true" *) arbitrationPipeline_t arbitrationPipeline_comb;
arbitrationPipeline_t arbitrationPipeline_reg;


// local slicer
typedef struct packed {
	logic [ADDRESSWIDTH-1:0] address;
	logic [REGISTERWIDTH-1:0] size;
} sliceBuffer_t;

typedef struct packed {
	logic [REGISTERWIDTH-1:0] size;
} sliceBufferSize_t;

//BEGIN SEND SLICING
sliceBuffer_t [SEND_CHANNELS-1:0] sliceBuffer_send_reg;
sliceBuffer_t [SEND_CHANNELS-1:0] sliceBuffer_send_comb;

sliceBufferSize_t [SEND_CHANNELS-1:0] sliceBufferCalc_send_reg;
sliceBufferSize_t [SEND_CHANNELS-1:0] sliceBufferCalc_send_comb;

logic [SEND_CHANNELS-1:0] sliceBuffer_send_zero_reg;
logic [$clog2(pcie::XILINX_MAX_PAYLOAD_SIZE+1)-1:0] sendTransferSize [SEND_CHANNELS-1:0]; //include 0

typedef union packed {
	logic [2:0] vector;
	struct packed {
		logic cmdAvail;
		logic cmdLimit;
		logic availLimit;
	} comp;
} sizeComparisonVector_t;

sizeComparisonVector_t sendComparisons;

for(genvar i=0; i<SEND_CHANNELS; ++i) begin : slicerLogicSend
	logic [$clog2(CHANNELS)-1:0] channelIndex = hardcoreConfig::channelInfoParser #(CHANNELS)::channelIDForMode(i, CHANNEL_MODES, hardcoreConfig::CM_READ_ONLY);

	logic [MAX_RESERVE_BITS-1:0] sendReserved_comb;
	logic [MAX_RESERVE_BITS-1:0] sendReserved_reg;
	
	logic [MAX_RESERVE_BITS-1+1:0] sendAvailable_comb; //We add one extra bit to detect underflows.
	logic [MAX_RESERVE_BITS-1:0]   sendAvailable_reg;
	
	logic [MAX_RESERVE_BITS-1:0]   sendAvailablePrecompute_comb;
	logic [MAX_RESERVE_BITS-1:0]   sendAvailablePrecompute_reg;
		
	transferSendBeats_t sendBeats;
	transferSendBeats_t sendBeats_reg;

	logic precompareAmount = sendLink[i].amount != 0;
	logic precompareSend;//   = sliceBuffer_send_comb[i].size != 0;
	
	always_ff @(posedge clk) begin : slicerRegisters
		sliceBufferCalc_send_reg[i].size <= sliceBufferCalc_send_comb[i].size;
		sendValid_reg <= sendValid;
		
		if(reset) begin
			sliceBuffer_send_reg[i].size <= '0;
			sliceBuffer_send_zero_reg[i] <= 1;
			
			sendAvailable_reg            <= 0;
			sendReserved_reg             <= 0;
			
			nextSendCommand_reg          <= 0;
		end else begin
			sliceBuffer_send_reg[i]      <= sliceBuffer_send_comb[i];
			sliceBuffer_send_zero_reg[i] <= sliceBuffer_send_comb[i].size == 0;
			
			//TODO: factor out common subexpression?
			//FIXME: underflow protection for send available

			sendAvailable_reg            <= sendAvailable_comb;
			sendReserved_reg             <= sendReserved_comb;

			nextSendCommand_reg          <=  nextSendCommand;
			/*if(arbitrationSend.channelId == i && sendValid[i] && nextSendCommand) begin
				//sendAvailable_reg        <= sendLink[i].amount - sendReserved_reg                                              - transferSendBeats(sendTransferSize[i]);
				sendReserved_reg         <= sendReserved_reg   - (requestEngine.nextSendData & requestEngine.sourceChannel==i) + transferSendBeats(sendTransferSize[i]); //consumed =1 if channel is selected and next is sent
			end else begin
				//sendAvailable_reg        <= sendLink[i].amount - sendReserved_reg;
				sendReserved_reg         <= sendReserved_reg   - (requestEngine.nextSendData & requestEngine.sourceChannel==i); //consumed =1 if channel is selected and next is sent
			end*/
		end
			
		sendBeats_reg <= sendBeats;
		sendAvailablePrecompute_reg <= sendAvailablePrecompute_comb;
	end
	
	always_comb begin : sliceCompute
		automatic logic lastSendExecuted = arbitrationPipeline_reg.nextSourceChannel == i && sendValid_reg[i] && nextSendCommand_reg;
		automatic logic [REGISTERWIDTH-1:0] sendAmount;
		
		sendAmount = sendAvailable_reg << $clog2(256/8);
		
		registerfile.commandConsumed[channelIndex] = sliceBuffer_send_zero_reg[i] && nextSendCommand && i == arbitrationSend_reg.channelId && registerfile.commandValid[i];
		
		unique casez({sliceBuffer_send_zero_reg[i], registerfile.commandValid[channelIndex], nextSendCommand && i == arbitrationSend_reg.channelId && sendValid_reg[i]}) //TODO:send_valid_reg could be replaced by arbitration pipeline?
			//3'b110, 3'b111: begin
			3'b11?: begin
				sliceBuffer_send_comb[i].address = registerfile.commandAddress[channelIndex];
				sliceBuffer_send_comb[i].size    = registerfile.commandSize[channelIndex];
				
				sendComparisons.comp.cmdAvail    = registerfile.commandSize[channelIndex][REGISTERWIDTH-1:5] < sendAvailable_reg;
				sendComparisons.comp.cmdLimit    = registerfile.commandSize[channelIndex] < maxPayloadSize;
				
				precompareSend                   = registerfile.commandSize[channelIndex] != 0;
			end
			3'b0?1: begin
				sliceBuffer_send_comb[i].size    = sliceBufferCalc_send_reg[i].size;
				sliceBuffer_send_comb[i].address = sliceBuffer_send_reg[i].address + arbitrationPipeline_reg.sizeSend;
				
				sendComparisons.comp.cmdAvail    = sliceBufferCalc_send_reg[i].size[REGISTERWIDTH-1:5] < sendAvailable_reg;
				sendComparisons.comp.cmdLimit    = sliceBufferCalc_send_reg[i].size < maxPayloadSize;
				
				precompareSend                   = sliceBufferCalc_send_reg[i].size != 0;
			end
			//default:
			//3'b000, 3'b010, 3'b100, 3'b101: begin
			3'b0?0, 3'b10?: begin
				sliceBuffer_send_comb[i]         = sliceBuffer_send_reg[i];
				
				sendComparisons.comp.cmdAvail    = sliceBuffer_send_reg[i].size[REGISTERWIDTH-1:5] < sendAvailable_reg;
				sendComparisons.comp.cmdLimit    = sliceBuffer_send_reg[i].size < maxPayloadSize;
				
				precompareSend                   = !sliceBuffer_send_zero_reg[i]; 
			end			
		endcase		
		
		sendComparisons.comp.availLimit = (sendAvailable_reg) < maxPayloadSize[$clog2(pcie::XILINX_MAX_PAYLOAD_SIZE+1)-1:$clog2(256/8)]; //TODO: asser 256/8 < XILINX_MIN_PAYLOAD_SIZE (the later is equivalent to the number of guranteed zeros for maxPayloadSize

		//This slows it down
		//sendValid[i] = (sendComparisons.comp.cmdAvail && !sendComparisons.comp.cmdLimit) || (!sendComparisons.comp.cmdAvail && !sendComparisons.comp.availLimit) || (sendLink[i].triggerSend && ((sendComparisons.comp.cmdAvail && sendComparisons.comp.cmdLimit && precompareSend) || (!sendComparisons.comp.cmdAvail && sendComparisons.comp.availLimit && precompareAmount)));

		unique casez(sendComparisons.vector)
			3'b0?0, 3'b10?: begin
				sendTransferSize[i] = maxPayloadSize;
				sliceBufferCalc_send_comb[i].size = sliceBuffer_send_comb[i].size - maxPayloadSize;
				sendValid[i]        = 1;
			end
			3'b0?1: begin
				sendTransferSize[i] = sendAmount;
				sliceBufferCalc_send_comb[i].size = sliceBuffer_send_comb[i].size - sendAmount;
				sendValid[i]        = precompareAmount && sendLink[i].triggerSend;
			end
			3'b11?: begin
				sendTransferSize[i] = sliceBuffer_send_comb[i].size;
				sliceBufferCalc_send_comb[i].size = 0;
				sendValid[i]        = precompareSend && sendLink[i].triggerSend;
			end
		endcase
		
		sendBeats = transferSendBeats(arbitrationPipeline_reg.sizeSend);
		
//		sendAvailable_comb      = sendLink[i].amount - sendReserved_reg;
		sendAvailable_comb = {1'b0, sendAvailablePrecompute_reg} - transferSendBeats(maxPayloadSize);
		
		unique casez({lastSendExecuted, sendAvailable_comb[$left(sendAvailable_comb)]})
			2'b0?: begin
				sendAvailable_comb = sendLink[i].amount - sendReserved_reg;
			end			
			2'b10: begin //dummy case, currently a noop
				sendAvailable_comb = sendAvailable_comb;
			end
			2'b11: begin
				sendAvailable_comb = 0;
			end
		endcase
		
		sendReserved_comb  = sendReserved_reg  - (requestEngine.nextSendData & requestEngine.sourceChannel==i);
		
		if(lastSendExecuted) begin
			sendReserved_comb  = sendReserved_comb  + sendBeats_reg;
		end
		
		sendAvailablePrecompute_comb = sendLink[i].amount - sendReserved_comb;
	end
end
//END SEND SLICING

//BEGIN RECEIVE SLICING
sliceBuffer_t [RECEIVE_CHANNELS-1:0] sliceBuffer_receive_reg;
sliceBuffer_t [RECEIVE_CHANNELS-1:0] sliceBuffer_receive_comb;

sliceBufferSize_t [RECEIVE_CHANNELS-1:0] sliceBufferCalc_receive_reg;
sliceBufferSize_t [RECEIVE_CHANNELS-1:0] sliceBufferCalc_receive_comb;

logic [RECEIVE_CHANNELS-1:0] sliceBuffer_receive_zero_reg;
logic [$clog2(pcie::XILINX_MAX_PAYLOAD_SIZE+1)-1:0] receiveTransferSize [SEND_CHANNELS-1:0]; //include 0

for(genvar i=0; i<RECEIVE_CHANNELS; ++i) begin : slicerLogicReceive
	logic [$clog2(CHANNELS)-1:0] channelIndex = hardcoreConfig::channelInfoParser #(CHANNELS)::channelIDForMode(i, CHANNEL_MODES, hardcoreConfig::CM_WRITE_ONLY);
	
	always_ff @(posedge clk) begin : slicerRegisters
		sliceBufferCalc_receive_reg[i] <= sliceBufferCalc_receive_comb[i];
		
		if(reset) begin
			sliceBuffer_receive_reg[i].size <= '0;
			sliceBuffer_receive_zero_reg[i] <= 1;
		end else begin
			sliceBuffer_receive_reg[i]      <= sliceBuffer_receive_comb[i];
			sliceBuffer_receive_zero_reg[i] <= sliceBuffer_receive_comb[i].size == 0; //[$clog2(pcie::XILINX_MAX_SIZE)-1:0] //FIXME: need to get the size from the core
		end
	end
	
	always_comb begin : sliceCompute
		//sliceBuffer_receive_comb[i] = sliceBuffer_receive_reg[i];
		logic cmdSizeMaxRequestSize;
		
		registerfile.commandConsumed[channelIndex] = 0;

		/*if(sliceBuffer_receive_zero_reg) begin
			//no command loaded
			if(registerfile.commandValid[channelIndex]) begin
				sliceBuffer_receive_comb[i].address = registerfile.commandAddress[channelIndex];
				sliceBuffer_receive_comb[i].size    = registerfile.commandSize[channelIndex];
					
				registerfile.commandConsumed[channelIndex] = 1;
			end
		end else if(nextReceiveCommand && i == arbitrationReceive_reg.channelId) begin
			sliceBuffer_receive_comb[i] = sliceBufferCalc_receive_reg[i];
			sliceBuffer_receive_comb[i].address = sliceBuffer_receive_reg[i].address + arbitrationPipeline_reg.sizeReceive;
		end*/
		
		unique casez({sliceBuffer_receive_zero_reg, registerfile.commandValid[channelIndex], nextReceiveCommand && i == arbitrationReceive_reg.channelId})
			3'b0?1: begin
				sliceBuffer_receive_comb[i].size    = sliceBufferCalc_receive_reg[i].size;
				sliceBuffer_receive_comb[i].address = sliceBuffer_receive_reg[i].address + arbitrationPipeline_reg.sizeReceive;
				
				cmdSizeMaxRequestSize               = sliceBufferCalc_receive_reg[i].size < maxRequestSize;
			end
			3'b10?, 3'b0?0: begin
				sliceBuffer_receive_comb[i]         = sliceBuffer_receive_reg[i];
				
				cmdSizeMaxRequestSize               = sliceBuffer_receive_reg[i].size < maxRequestSize;
			end
			3'b11?: begin
				sliceBuffer_receive_comb[i].size    = registerfile.commandSize[channelIndex];
				sliceBuffer_receive_comb[i].address = registerfile.commandAddress[channelIndex];
					
				cmdSizeMaxRequestSize               = registerfile.commandSize[channelIndex] < maxRequestSize;
					
				registerfile.commandConsumed[channelIndex] = 1;
			end
		endcase

		//sliceBufferCalc_receive_comb[i].size    = sliceBuffer_receive_comb[i].size    - arbitrationReceive.size;
	
		receiveValid[i] = sliceBuffer_receive_comb[i].size != 0;
	
		if(cmdSizeMaxRequestSize) begin
			receiveTransferSize[i] = sliceBuffer_receive_comb[i].size;
			sliceBufferCalc_receive_comb[i].size    = 0;//sliceBuffer_receive_comb[i].size - sliceBuffer_receive_comb[i].size;
		end else begin
			receiveTransferSize[i] = maxRequestSize;
			sliceBufferCalc_receive_comb[i].size    = sliceBuffer_receive_comb[i].size - maxRequestSize;
		end
		//TODO rewrite this as a three way parallel min, rther than two successive min operations?
		//TODO update actual receive buffer available size
	end
end
//END RECEIVE SLICING

//TODO: more efficient arbitration: do not trigger new requests early

/*BEGIN source this out into a usermodule ======================================*/
/*
 * Interface: provided on the vector of available data/space decide which send/recieve to dispatch next. rovide IDs of next send/receive.
 */



/*
 * Altera cookbook style arbitration: least significant bit has highest riority, no fairness
 * = sendValid & ^(sendValid-1);
 */

logic [RECEIVE_CHANNELS-1:0] receiveOneHotArbitration;
logic [SEND_CHANNELS-1:0]    sendOneHotArbitration;

assign receiveOneHotArbitration = receiveValid & ~(receiveValid-1);
assign sendOneHotArbitration    = sendValid & ~(sendValid-1);

oneHotDecoder #(
	.VALUES(RECEIVE_CHANNELS)
) inputDecoder (
	.oneHotVector(receiveOneHotArbitration),
	.binary(arbitrationReceive.channelId)
);

oneHotDecoder #(
	.VALUES(SEND_CHANNELS)
) outputDecoder (
	.oneHotVector(sendOneHotArbitration),
	.binary(arbitrationSend.channelId)
);

logic [DATAWIDTH-1:0] sendDataAccessor     [SEND_CHANNELS-1:0]; //sidestep the brainfuck, that we can not access an array of interfaces (sendLink[i]) at will.
logic [DATAWIDTH-1:0] receiveDataAccessor  [RECEIVE_CHANNELS-1:0];
logic [BYTES-1:0]     receiveValidAccessor [RECEIVE_CHANNELS-1:0];
logic                 receiveFlushAccessor [RECEIVE_CHANNELS-1:0];

for(genvar i=0; i<SEND_CHANNELS; ++i) begin : sendInterfaceAccessor
	assign sendLink[i].next     = requestEngine.nextSendData && i == arbitrationSend_reg.channelId;
	assign sendDataAccessor[i]  = sendLink[i].data;
end

for(genvar i=0; i<RECEIVE_CHANNELS; ++i) begin : receiveInterfaceAccessor
	assign receiveLink[i].data  = receiveDataAccessor[i];
	assign receiveLink[i].valid = receiveValidAccessor[i];
	assign receiveLink[i].flush = receiveFlushAccessor[i];
	//DONE above: assign registerfile.commandConsumed[i] = (CHANNEL_MODES[i] == hardcoreConfig::CM_READ_ONLY && i == sendChannel && requestEngine.nextSendCommand) || (CHANNEL_MODES[i] == hardcoreConfig::CM_WRITE_ONLY && i == receiveChannel && requestEngine.nextReceiveCommand);
end

/*END   source this out into a usermodule ======================================*/

always_ff @(posedge clk) begin : Registers
	if(reset) begin
		arbitrationSend_reg.channelId <= '0;
		
		arbitrationReceive_reg.channelId <= '0;
	end else begin
		arbitrationSend_reg    <= arbitrationSend;
		arbitrationReceive_reg <= arbitrationReceive;
	end
end

//=== Pipeline [Decoupling of arbitration] =====

//TODO: extend the no channel code to eliminate the arbitration all together for 0 channels. Extend to receive side as well
generate
if(SEND_CHANNELS>0) begin
	assign requestEngine.sizeSend               = arbitrationPipeline_reg.sizeSend;
	assign requestEngine.addressSend            = arbitrationPipeline_reg.addressSend;
	assign requestEngine.validSendCommand       = arbitrationPipeline_reg.validSendCommand;
	assign requestEngine.finalizeSendCommand    = arbitrationPipeline_reg.finalizeSendCommand;
	assign requestEngine.nextSourceChannel      = arbitrationPipeline_reg.nextSourceChannel;
end else begin
	assign requestEngine.sizeSend               = '0;
	assign requestEngine.addressSend            = '0;
	assign requestEngine.validSendCommand       =  0;
	assign requestEngine.finalizeSendCommand    = '0;
	assign requestEngine.nextSourceChannel      = '0;	
end
endgenerate

assign requestEngine.sizeReceive            = arbitrationPipeline_reg.sizeReceive;
assign requestEngine.addressReceive         = arbitrationPipeline_reg.addressReceive;
assign requestEngine.validReceiveCommand    = arbitrationPipeline_reg.validReceiveCommand;
assign requestEngine.finalizeReceiveCommand = arbitrationPipeline_reg.finalizeReceiveCommand;
assign requestEngine.channelReceive         = arbitrationPipeline_reg.channelReceive;

always_comb begin : arbitrationPipeline
	arbitrationPipeline_comb = arbitrationPipeline_reg;
	
	nextSendCommand    = !arbitrationPipeline_reg.validSendCommand    || requestEngine.nextSendCommand;
	nextReceiveCommand = !arbitrationPipeline_reg.validReceiveCommand || requestEngine.nextReceiveCommand;
	
	if(nextSendCommand) begin
		arbitrationPipeline_comb.addressSend         = sliceBuffer_send_comb[arbitrationSend.channelId].address;
		arbitrationPipeline_comb.sizeSend            = sendTransferSize[arbitrationSend.channelId];
		arbitrationPipeline_comb.validSendCommand    = sendValid[arbitrationSend.channelId]; //sliceBuffer_send_comb[arbitrationSend.channelId].size != 0;
		arbitrationPipeline_comb.finalizeSendCommand = sliceBuffer_send_comb[arbitrationSend_reg.channelId].size <= maxPayloadSize;
		arbitrationPipeline_comb.nextSourceChannel   = arbitrationSend.channelId;
	end
	
	if(nextReceiveCommand) begin
		arbitrationPipeline_comb.addressReceive         = sliceBuffer_receive_comb[arbitrationReceive.channelId].address;
		arbitrationPipeline_comb.sizeReceive            = receiveTransferSize[arbitrationReceive.channelId];
		arbitrationPipeline_comb.validReceiveCommand    = receiveValid[arbitrationReceive.channelId]; //sliceBuffer_receive_comb[arbitrationReceive.channelId].size != 0;
		arbitrationPipeline_comb.finalizeReceiveCommand = sliceBuffer_receive_comb[arbitrationReceive.channelId].size <= maxRequestSize;
		arbitrationPipeline_comb.channelReceive         = arbitrationReceive.channelId;
	end
	
	for(int i=0; i<RECEIVE_CHANNELS; ++i) begin
		receiveDataAccessor [i] = requestEngine.dataReceive;
		receiveValidAccessor[i] = '0;
		receiveFlushAccessor[i] = 0;
	end
	
	requestEngine.dataSend               = sendDataAccessor[requestEngine.sourceChannel];
	receiveValidAccessor[requestEngine.channelDestination] = requestEngine.validReceiveData;
	receiveFlushAccessor[requestEngine.channelDestination] = requestEngine.write;
end

always_ff @(posedge clk) begin : StaticArbitrationResult
	arbitrationPipeline_reg                         <= arbitrationPipeline_comb;
	
	if(reset) begin
		arbitrationPipeline_reg.validReceiveCommand <= 0;
		arbitrationPipeline_reg.validSendCommand    <= 0;
	end
end

//=== Interrupt generation ===
always_ff @(posedge clk) begin : INTERRUPT_GENERATOR
	//TODO: delay interrupts till queues are low
	requestEngine.interruptRequests = requestEngine.completedSendCommand || requestEngine.completedReceiveCommand; //TODO: user generated interrupts

	for(int i=0; i<SEND_CHANNELS; ++i) begin
		logic [$clog2(CHANNELS)-1:0] channelIndex = hardcoreConfig::channelInfoParser #(CHANNELS)::channelIDForMode(i, CHANNEL_MODES, hardcoreConfig::CM_READ_ONLY);
		
		if(requestEngine.completedSendCommand && i == requestEngine.sourceChannel) begin
			registerfile.commandCompleted[channelIndex] <= 1;
		end else begin
			registerfile.commandCompleted[channelIndex] <= 0;
		end
	end
	
	for(int i=0; i<RECEIVE_CHANNELS; ++i) begin : slicerLogicReceive
		logic [$clog2(CHANNELS)-1:0] channelIndex = hardcoreConfig::channelInfoParser #(CHANNELS)::channelIDForMode(i, CHANNEL_MODES, hardcoreConfig::CM_WRITE_ONLY);
		
		if( requestEngine.completedReceiveCommand && i == requestEngine.channelDestination) begin
			registerfile.commandCompleted[channelIndex] <= 1;
		end else begin
			registerfile.commandCompleted[channelIndex] <= 0;
		end
	end
	
end

endmodule