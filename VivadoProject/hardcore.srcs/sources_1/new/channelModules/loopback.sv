module loopback(
	input logic clk,
	input logic reset,
	Adapter2Arbiter_send.adapter arbiterSend,
	Adapter2Arbiter_receive.adapter arbiterReceive
);

	Adapter2Module_receive receive();
	Adapter2Module_send send();

	moduleAdapter #(
		.DATAWIDTH           (pcieInterfaces::INTERFACEWIDTH),
		.BUFFER_SEND_DEPTH   (4),
		.BUFFER_RECEIVE_DEPTH(32),
		.PRESTALL_OUPUT      (0),
		.WIRESPEEDMODULE     (0) //FIXME
	)
	bufferingAdapter (
		.clk           (clk),
		.reset         (reset),
		.arbiterReceive(arbiterReceive),
		.arbiterSend   (arbiterSend),
		.moduleReceive (receive),
		.moduleSend    (send)
	);


/**
	assign send.triggerSend  = 0;

	assign send.data     = receive.data;
	assign send.valid    = receive.valid;
	assign receive.ready = send.ready; /**/
	
	/*(* mark_debug = "true" *)*/ logic [pcieInterfaces::INTERFACEWIDTH-1:0] data_reg;
	/*(* mark_debug = "true" *)*/ logic valid_reg;
	
	//(* mark_debug = "true" *) logic [pcieInterfaces::INTERFACEWIDTH-1:0] DEBUG_reg;
	//(* mark_debug = "true" *) logic DEBUG_VALID;
	//(* mark_debug = "true" *) logic DEBUG_READY;
	
	
	//FIXME disable first word fallthrough in the buffering adapter 
	always_ff @(posedge clk) begin : BUFFER
		//receive.ready <= 0;
		
		if(reset) begin
			valid_reg <= 0;
			/*DEBUG_reg <= '0;
			DEBUG_VALID <= 0;
			DEBUG_READY <= 0;*/
			data_reg <= '0;
		end else begin
			/*DEBUG_reg <= arbiterReceive.data;
			DEBUG_VALID <= arbiterReceive.valid;
			DEBUG_READY <= send.ready;*/
			data_reg <= receive.data;
			if(!valid_reg || send.ready) begin
				//receive.ready <= 1;
				//data_reg  <= receive.data;
				valid_reg <= receive.valid;
			end
		end
	end
	
	//assign send.data  = data_reg;
	//assign send.valid = valid_reg;
	
	assign send.data = receive.data;
	assign send.valid = receive.valid && send.ready;
	assign receive.ready = send.ready && receive.valid;
	
	assign send.triggerSend = 0;

endmodule