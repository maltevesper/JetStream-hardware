import pcieInterfaces::*;
import fifoPkg::*;

interface Adapter2Arbiter_send # (
	DATAWIDTH = pcieInterfaces::INTERFACEWIDTH,
	BUFFERSIZE = 1024 //TODO: define this reasonable
);
	logic [DATAWIDTH-1:0] data;
	
	logic [$clog2(BUFFERSIZE+1)-1:0] amount;

	logic triggerSend;
	logic next; //TODO: is this ready?
	
	modport arbiter(
		input  data,
		input  amount,
		input  triggerSend,
		output next
	);
	
	modport adapter(
		output data,
		output amount,
		output triggerSend,
		input  next
	);
endinterface

interface Adapter2Arbiter_receive # (
	DATAWIDTH  = pcieInterfaces::INTERFACEWIDTH,
	BUFFERSIZE = 1024, //TODO: define this reasonable
	BYTEWIDTH  = pcieInterfaces::BYTEBITS
);
	logic [DATAWIDTH-1:0] data;
	logic [$clog2(BUFFERSIZE+1)-1:0] amount;
	logic [DATAWIDTH/BYTEWIDTH-1:0]  valid;
	logic flush;
	
	modport arbiter(
		output data,
		input  amount,
		output valid,
		output flush
	);
	
	modport adapter(
		input  data,
		output amount,
		input  valid,
		input  flush
	);
endinterface

interface Adapter2Module_send # (
	DATAWIDTH = pcieInterfaces::INTERFACEWIDTH
);

	logic [DATAWIDTH-1:0] data;
	logic triggerSend;
	logic valid;
	logic ready;
	
	modport adapter(
		input  data,
		input  triggerSend,
		input  valid,
		output ready
	);
	
	modport core(
		output data,
		output triggerSend,
		output valid,
		input  ready
	);

endinterface

interface Adapter2Module_receive # (
	DATAWIDTH = pcieInterfaces::INTERFACEWIDTH,
	BYTEWIDTH = pcieInterfaces::BYTEBITS
);

	logic [DATAWIDTH-1:0] data;
	logic valid;
	logic [DATAWIDTH/BYTEWIDTH-1:0] validVector;
	logic ready;
	
	modport adapter(
		output data,
		output valid,
		output validVector,
		input  ready
	);
	
	modport core(
		input  data,
		input  valid,
		input  validVector,
		output ready
	);

endinterface

module writeCombiner #(
	parameter int DATAWIDTH = pcieInterfaces::INTERFACEWIDTH,
	parameter int BYTEWIDTH = pcieInterfaces::BYTEBITS
)(
	input logic clk,
	input logic reset,
	Adapter2Arbiter_receive.adapter adapter,
	Adapter2Arbiter_receive.arbiter arbiter
);
	localparam int BYTES = DATAWIDTH/BYTEWIDTH;	
	
	logic [DATAWIDTH/BYTEWIDTH-1:0] validVector_comb;
	logic [DATAWIDTH/BYTEWIDTH-1:0] validVector_reg;
	logic [DATAWIDTH-1:0] data_comb;
	logic [DATAWIDTH-1:0] data_reg;

	always_ff @(posedge clk) begin : register
		if(reset || arbiter.flush) begin
			validVector_reg <= '0;
		end else begin
			validVector_reg <= validVector_comb;
		end
		
		data_reg <= data_comb;
	end

	assign adapter.data  = data_comb;
	assign adapter.valid = validVector_comb;
	assign adapter.flush = arbiter.flush;

	generate
	for(genvar i=0; i<DATAWIDTH/BYTEWIDTH; i++) begin
		always_comb begin
			validVector_comb = validVector_reg | arbiter.valid;
			
			//foreach(arbiter.valid[i]) begin

			if(arbiter.valid[i]) begin
				data_comb[(i+1)*BYTEWIDTH-1:i*BYTEWIDTH] = arbiter.data[(i+1)*BYTEWIDTH-1:i*BYTEWIDTH];
			end else begin
				data_comb[(i+1)*BYTEWIDTH-1:i*BYTEWIDTH] = data_reg[(i+1)*BYTEWIDTH-1:i*BYTEWIDTH];
			end
		end
	end
	endgenerate
endmodule

module moduleAdapter #(
	parameter int DATAWIDTH = pcieInterfaces::INTERFACEWIDTH,
	parameter int BYTEWIDTH = pcieInterfaces::BYTEBITS,
	parameter int BUFFER_SEND_DEPTH = 2,
	parameter int BUFFER_RECEIVE_DEPTH = 2,
	parameter int PRESTALL_OUPUT = 0,     //retract the sendReady signal, when less than this many outputs can be buffered.
	parameter logic WIRESPEEDMODULE = 0,
	parameter logic KEEPVALID = 1
)(
	input logic clk,
	input logic reset,
	Adapter2Arbiter_receive.adapter arbiterReceive,
	Adapter2Arbiter_send.adapter    arbiterSend,
	
	Adapter2Module_receive.adapter  moduleReceive,
	Adapter2Module_send.adapter     moduleSend
);
	localparam int BYTES = DATAWIDTH/BYTEWIDTH;
	
	
	fifoConnect #(
		.WIDTH(KEEPVALID?DATAWIDTH+BYTES:DATAWIDTH),
		.DEPTH(BUFFER_RECEIVE_DEPTH)
	)
	inputFifo ();
	
	fifo #(
		.WIDTH             (KEEPVALID?DATAWIDTH+BYTES:DATAWIDTH),
		.DEPTH             (BUFFER_RECEIVE_DEPTH),
		.OUTPUTS           (FIFO_VALID),
		.FIRSTWORD_FALLTHROUGH(0)
	)
	inputFifo_module (
		.clk     (clk),
		.reset   (reset),
		.circular(0),
		.link    (inputFifo)
	);
	
	generate
	if(KEEPVALID) begin
		assign inputFifo.datain          = {arbiterReceive.valid, arbiterReceive.data};
		assign moduleReceive.validVector = inputFifo.dataout[DATAWIDTH+BYTES-1:DATAWIDTH];
	end else begin
		assign inputFifo.datain          = arbiterReceive.data;
		assign moduleReceive.validVector = '1;
	end
	endgenerate
	
	assign inputFifo.write      = arbiterReceive.flush;
	
	assign moduleReceive.data   = inputFifo.dataout[DATAWIDTH-1:0];
	assign moduleReceive.valid  = inputFifo.fillStatus.valid;
	assign inputFifo.read       = moduleReceive.ready;
	
	fifoConnect #(
		.WIDTH(DATAWIDTH),
		.DEPTH(BUFFER_SEND_DEPTH)
	)
	outputFifo ();
	
	fifo #(
		.WIDTH             (DATAWIDTH),
		.DEPTH             (BUFFER_SEND_DEPTH),
		.OUTPUTS           (FIFO_ALMOST_FULL | FIFO_FULL),
		.TRIGGERALMOSTFULL (PRESTALL_OUPUT),
		.FIRSTWORD_FALLTHROUGH(0)
	)
	outputFifo_module (
		.clk     (clk),
		.reset   (reset),
		.circular(0),
		.link    (outputFifo)
	);
	
	assign outputFifo.datain = moduleSend.data;
	assign outputFifo.write  = moduleSend.valid;
	assign moduleSend.ready  = !outputFifo.fillStatus.almostFull;
	
	assign arbiterSend.data        = outputFifo.dataout;
	assign outputFifo.read         = arbiterSend.next;
	
	assign arbiterSend.triggerSend = outputFifo.fillStatus.full | moduleSend.triggerSend; //TODO: Trigger only if input buffer is full as well for wirespeed modules. What about other moudles?
	
	always_comb begin
		if(!WIRESPEEDMODULE) begin
			arbiterReceive.amount = BUFFER_RECEIVE_DEPTH - inputFifo.fillLevel;
			arbiterSend.amount    = outputFifo.fillLevel;
		end else begin
			if(BUFFER_SEND_DEPTH <= 1) begin
				arbiterReceive.amount = BUFFER_RECEIVE_DEPTH - inputFifo.fillLevel;
				arbiterSend.amount    = inputFifo.fillLevel;
			end else if(BUFFER_RECEIVE_DEPTH <= 1) begin
				arbiterReceive.amount = BUFFER_SEND_DEPTH - outputFifo.fillLevel;
				arbiterSend.amount    = outputFifo.fillLevel;
			end else begin
				arbiterReceive.amount = BUFFER_RECEIVE_DEPTH - inputFifo.fillLevel + BUFFER_SEND_DEPTH - outputFifo.fillLevel;
				arbiterSend.amount    = outputFifo.fillLevel + inputFifo.fillLevel;
			end
		end
	end

endmodule

module moduleAdapterSend #(
	parameter int DATAWIDTH = pcieInterfaces::INTERFACEWIDTH,
	parameter int BUFFER_SEND_DEPTH = 1,
	parameter int PRESTALL_OUPUT = 0,     //retract the sendReady signal, when less than this many outputs can be buffered.
	parameter logic WIRESPEEDMODULE = 0
)(
	input logic clk,
	input logic reset,
	Adapter2Arbiter_send.adapter    arbiterSend,
	
	Adapter2Module_send.adapter     moduleSend
);

	fifoConnect #(
		.WIDTH(DATAWIDTH),
		.DEPTH(BUFFER_SEND_DEPTH)
	)
	outputFifo ();
	
	fifo #(
		.WIDTH             (DATAWIDTH),
		.DEPTH             (BUFFER_SEND_DEPTH),
		.OUTPUTS           (FIFO_ALMOST_FULL | FIFO_FULL),
		.TRIGGERALMOSTFULL (PRESTALL_OUPUT)
	)
	outputFifo_module (
		.clk     (clk),
		.reset   (reset),
		.circular(0),
		.link    (outputFifo)
		);
	
	assign outputFifo.datain = moduleSend.data;
	assign outputFifo.write  = moduleSend.valid;
	assign moduleSend.ready  = !outputFifo.fillStatus.almostFull;
	
	assign arbiterSend.data        = outputFifo.dataout;
	assign outputFifo.read         = arbiterSend.next;
	
	assign arbiterSend.triggerSend = outputFifo.fillStatus.full | moduleSend.triggerSend;
	
	always_comb begin
		if(!WIRESPEEDMODULE) begin
			arbiterSend.amount    = outputFifo.fillLevel;
		end else begin
			arbiterSend.amount    = '1;
		end
	end

endmodule

module moduleAdapterReceive #(
	parameter int DATAWIDTH = pcieInterfaces::INTERFACEWIDTH,
	parameter int BYTEWIDTH = pcieInterfaces::BYTEBITS,
	parameter int BUFFER_RECEIVE_DEPTH = 1,
	parameter logic WIRESPEEDMODULE = 0,
	parameter logic KEEPVALID = 1
)(
	input logic clk,
	input logic reset,
	Adapter2Arbiter_receive.adapter arbiter,
	Adapter2Module_receive.adapter  moduleReceive
);
	
	localparam int BYTES = DATAWIDTH/BYTEWIDTH;
	
	Adapter2Arbiter_receive combiner();

	writeCombiner #(
		.DATAWIDTH(DATAWIDTH),
		.BYTEWIDTH(BYTEWIDTH)
	)
	u_writeCombiner (
		.clk    (clk),
		.reset  (reset),
		.adapter(combiner),
		.arbiter(arbiter)
	);

	//put input fifo
	
	fifoConnect #(
		.WIDTH(DATAWIDTH),
		.DEPTH(BUFFER_RECEIVE_DEPTH)
	)
	inputFifo ();
	
	fifo #(
		.WIDTH             (KEEPVALID?DATAWIDTH+BYTES:DATAWIDTH),
		.DEPTH             (BUFFER_RECEIVE_DEPTH),
		.OUTPUTS           (FIFO_VALID)
	)
	inputFifo_module (
		.clk     (clk),
		.reset   (reset),
		.circular(0),
		.link    (inputFifo)
	);
	
	generate
	if(KEEPVALID) begin
		assign inputFifo.datain          = {combiner.valid, combiner.data};
		assign moduleReceive.validVector = inputFifo.dataout[DATAWIDTH+BYTES-1:DATAWIDTH];
	end else begin
		assign inputFifo.datain          = combiner.data;
		assign moduleReceive.validVector = '1;
	end
	endgenerate
	
	assign inputFifo.write      = combiner.flush;
	
	assign moduleReceive.data   = inputFifo.dataout;
	assign moduleReceive.valid  = inputFifo.fillStatus.valid;
	assign inputFifo.read       = moduleReceive.ready;
	
	always_comb begin
		if(!WIRESPEEDMODULE) begin
			arbiter.amount = BUFFER_RECEIVE_DEPTH - inputFifo.fillLevel;
		end else begin
			arbiter.amount = '1;
		end
	end

endmodule
