//`include "pcieInterfaces.sv"

import pcieHeaders::*;

module completionEngine # (
	parameter int CHANNELS      =  2,
	parameter hardcoreConfig::channelMode_t [0:CHANNELS-1] CHANNEL_MODES = '{default: hardcoreConfig::CM_NOT_PRESENT},
	parameter hardcoreConfig::channelType_t [0:CHANNELS-1] CHANNEL_TYPES = '{default: hardcoreConfig::CT_GENERIC},
	parameter int DEPTH         =  8, //depth in circular buffers for the channels
	parameter int REGISTERWIDTH = 32,
	parameter int CHANNELADDRESSBITS = 3,
	parameter int ADDRESSBIT_OFFSET = 2
)(
	input logic clk,
	input logic reset,
	pcie_completerRequest.userLogic    completerRequest,
	pcie_completerCompletion.userLogic completerCompletion,
	
	registerfileConnector.userLogic    registerfile,
	output logic [255:0] data,
	output logic valid
	//(* MARK_DEBUG ="TRUE" *) output logic [6:ADDRESSBIT_OFFSET] addressDebugSignal
);

//assign addressDebugSignal =  registerfile.addressRead;

typedef enum logic [0:0] {REQUESTER_IDLE, REQUESTER_RECEIVE} requesterState_Type;
typedef enum logic [1:0] {COMPLETER_IDLE, COMPLETER_COMPLETE_ONE_WRITE, COMPLETER_COMPLETE_TWO_WRITES, COMPLETER_WRITING} completerState_Type;
localparam BUFFERED_ADDRESSBITS = ADDRESSBIT_OFFSET + CHANNELADDRESSBITS + $clog2(CHANNELS+1);
localparam SINKCHANNELBASE = 1024;
localparam SINKCHANNELWIDTH = 256; //SHOULD be >= MAX_PAYLOAD

typedef struct packed {
	logic  [2:0]  attributes;
	logic  [2:0]  transactionClass;
	logic  [7:0]  target;
	logic  [7:0]  tag;
	logic [15:0]  requesterID;
	logic [10:0]  dwords;
	logic [12:0]  bytes;
	pcieHeaders::AddressTypeEncoding addressType;
	logic  [BUFFERED_ADDRESSBITS-1:0]  address;
} requestDependentCompletion_t;

fifoConnect #(
	.WIDTH($bits(requestDependentCompletion_t)),
	.DEPTH(4)
) readFifoLink();

fifo #(
	.WIDTH             ($bits(requestDependentCompletion_t)),
	.DEPTH             (4),
	.TRIGGERALMOSTFULL (1),
	.TRIGGERALMOSTEMPTY(1)
) readFifoaddressWrite (
	.clk     (clk),
	.reset   (reset),
	.circular(0),
	.link    (readFifoLink)
);

pcieHeaders::completerRequestMemory memoryHeader = pcieHeaders::completerRequestMemory'(completerRequest.data);
	
requestDependentCompletion_t currentCompletion = requestDependentCompletion_t'(readFifoLink.dataout);
pcieHeaders::completerCompletion completion;

//Dynamic comletion part
assign completion.address              = currentCompletion.address;
assign completion.addressType          = currentCompletion.addressType;
assign completion.dwords               = currentCompletion.dwords;
assign completion.requesterID          = currentCompletion.requesterID;
assign completion.tag                  = currentCompletion.tag;
assign completion.target               = currentCompletion.target;
assign completion.transactionClass     = currentCompletion.transactionClass;
assign completion.attributes           = currentCompletion.attributes;
assign completion.bytes                = currentCompletion.bytes;

//Static completion part
assign completion.lockedReadCompletion = 0;
assign completion.status               = pcieHeaders::CC_SUCCESSFUL;
assign completion.posioned             = 0;
assign completion.bus                  = 0;
assign completion.completerIdEnable    = 0;
assign completion.forceECRC            = 0;

assign completion.reserved_0           = 0;
assign completion.reserved_1           = 0;
assign completion.reserved_2           = 0;
assign completion.reserved_3           = 0;

typedef struct packed {
	logic ready;
} completerRequest_outputs;

completerRequest_outputs completerRequest_comb;
completerRequest_outputs completerRequest_reg;

requesterState_Type requesterState_comb;
requesterState_Type requesterState_reg;
	
completerState_Type completerState_comb;
completerState_Type completerState_reg;

always_ff @(posedge clk) begin : registerProcess
	completerRequest_reg    <= completerRequest_comb;
	requesterState_reg      <= requesterState_comb;
	completerState_reg      <= completerState_comb;
end
	
assign data=completerRequest.data;	
	
always_comb begin : receiver
	pcieHeaders::HeaderType headerType = pcieHeaders::getHeaderType(completerRequest.data[127:0]);
	
	completerRequest_comb    = completerRequest_reg;
	
	requesterState_comb      = requesterState_reg;
	
	//TODO: tie this always to the same bits
	registerfile.addressWrite = 0;
	
	registerfile.dataWrite    = 0;
	
	readFifoLink.write  = 0;
	readFifoLink.datain = 0;
	
	valid = 0;
//CHECK ABOVE
	if(reset) begin
		requesterState_comb            = REQUESTER_IDLE;
		registerfile.write             = 0;
	end else begin
		registerfile.write             = 0;

		unique case(requesterState_reg)
			REQUESTER_IDLE: begin
				
				if(completerRequest.valid) begin
					unique case(headerType)
						pcieHeaders::MEM_WRITE: begin
								pcieHeaders::completerRequestMemory requestHeader = pcieHeaders::completerRequestMemory'(completerRequest.data[$bits(completerRequestMemory)-1:0]);
							
								//TODO: support 32 Byte writes, support longer writes, honor byte field??, range check address
							
								registerfile.addressWrite = requestHeader.address[$bits(registerfile.addressWrite)+2-1:2];
								registerfile.dataWrite = completerRequest.data[159:128];
								registerfile.write     = 1;
							
								valid = 1;
							
								if(requestHeader.dwordCount > pcieInterfaces::DWORDS - $bits(pcieHeaders::completerRequestMemory)/pcie::DWORDBITS) begin
									requesterState_comb = REQUESTER_RECEIVE;
								end
							end
						pcieHeaders::MEM_READ: begin
								pcieHeaders::completerRequestMemory requestHeader = pcieHeaders::completerRequestMemory'(completerRequest.data[$bits(completerRequestMemory)-1:0]);
								requestDependentCompletion_t dependentCompletion;
								
								logic [ADDRESSBIT_OFFSET-1:0] byteOffset;
							
								//begin leading zeros detector
								begin

								byteOffset = 0;

								if($increment(completerRequest.user.byteEnable_first)==1) begin
									//$left >= $right 
									for(int i=$right(completerRequest.user.byteEnable_first); i<=$left(completerRequest.user.byteEnable_first); i=i+$increment(completerRequest.user.byteEnable_first)) begin
										if(completerRequest.user.byteEnable_first[i+:1]==1) begin
											byteOffset = 0;
										end else begin
											byteOffset = byteOffset + 1;
										end
									end
								end else begin
									//$left<$right
									for(int i=$right(completerRequest.user.byteEnable_first); i>=$left(completerRequest.user.byteEnable_first); i=i+$increment(completerRequest.user.byteEnable_first)) begin
										if(completerRequest.user.byteEnable_first[i+:1]==1) begin
											byteOffset = 0;
										end else begin
											byteOffset = byteOffset + 1;
										end
									end
								end
								
								end
								//end leading zeros detector
								
								dependentCompletion.address              = {requestHeader.address[BUFFERED_ADDRESSBITS-1:ADDRESSBIT_OFFSET], byteOffset};
								dependentCompletion.addressType          = requestHeader.addressType;
								dependentCompletion.dwords               = requestHeader.dwordCount;
								dependentCompletion.requesterID          = requestHeader.requesterID;
								dependentCompletion.tag                  = requestHeader.tag;
								dependentCompletion.target               = requestHeader.target;
								dependentCompletion.transactionClass     = requestHeader.transactionClass;
								dependentCompletion.attributes           = requestHeader.attributes;
								
								if(completerRequest.user.byteEnable_first == '0 && completerRequest.user.byteEnable_last == '0) begin
									//zero byte read
									dependentCompletion.bytes = 1;
								end else begin
									//assumption: only DWORD aligned reads, in multiple DWORD size (would have to calculate according to PG023 Nov 19, 2014, TABLE 3-7 page 118).
									dependentCompletion.bytes = requestHeader.dwordCount << 2;
								end

								readFifoLink.datain = dependentCompletion;
								readFifoLink.write  = 1;
							end
						default: begin
						end
					endcase
				end
			end
			REQUESTER_RECEIVE: begin
				if(completerRequest.valid) begin
					valid = 1;
					
					if(completerRequest.last) begin
						requesterState_comb = REQUESTER_IDLE;
					end
				end
			end
		endcase
	end
end

assign completerCompletion.user.discontinue = 0;
assign completerCompletion.user.parity      = 0;

assign completerCompletion.keep  = {5'b00001,3'b111};  //{5'bPayloadKeepBits, 3'bKeepTheHeader} Constant assumes payload always equal to 1;
assign completerCompletion.last  = 1;



assign completerCompletion.data[$bits(pcieHeaders::completerCompletion)-1:0] = completion;
assign completerCompletion.data[$bits(pcieHeaders::completerCompletion)+32-1:$bits(pcieHeaders::completerCompletion)] = registerfile.dataRead; // 32'hbabeface; // 
assign completerCompletion.data[$left(completerCompletion.data):$bits(pcieHeaders::completerCompletion)+32] = '0;

assign registerfile.addressRead = currentCompletion.address[BUFFERED_ADDRESSBITS-1:ADDRESSBIT_OFFSET]; //TODO: fix to support more than 32 registers

always_comb begin : writer
	readFifoLink.read = 0;
	
	if(reset) begin
		completerState_comb = COMPLETER_IDLE;
		completerCompletion.valid = 0;
		completerRequest.ready = 0;
	end else begin
		completerState_comb = completerState_reg;

		completerCompletion.valid = readFifoLink.fillStatus.valid;
		completerRequest.ready = !readFifoLink.fillStatus.almostFull;

		unique case(completerState_reg)
			COMPLETER_IDLE: begin
				if(readFifoLink.fillStatus.valid) begin
					completerState_comb = COMPLETER_WRITING;
				end
			end
			COMPLETER_WRITING: begin
				if(completerCompletion.ready) begin
					readFifoLink.read = 1;
					
					if(readFifoLink.fillStatus.almostEmpty && !readFifoLink.write) begin
						completerCompletion.valid = 0;
						completerState_comb = COMPLETER_IDLE;
					end
				end
			end
		endcase
	end
end

endmodule