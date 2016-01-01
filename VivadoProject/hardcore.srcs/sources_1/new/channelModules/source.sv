module source(
	input logic clk,
	input logic reset,
	Adapter2Arbiter_send.adapter arbiterSend
);

	/*Adapter2Module_send send();

	moduleAdapterSend #(
		.DATAWIDTH           (pcieInterfaces::INTERFACEWIDTH),
		.BUFFER_SEND_DEPTH   (),
		.PRESTALL_OUPUT      (0),
		.WIRESPEEDMODULE     (1)
	)
	bufferingAdapter (
		.clk           (clk),
		.reset         (reset),
		.arbiterSend   (arbiterSend),
		.moduleSend    (send)
	);*/


/**
	assign send.triggerSend  = 0;

	assign send.data     = receive.data;
	assign send.valid    = receive.valid;
	assign receive.ready = send.ready; /**/
	
	logic [pcieInterfaces::INTERFACEWIDTH-1:0] data_reg;
	
	always_ff @(posedge clk) begin : BUFFER	
		if(reset) begin
			data_reg = 'hbabeface0000;
		end else begin
			if(arbiterSend.next) begin
				data_reg[31:0]  <= data_reg[31:0] + 1;
			end
		end
	end
	
	assign arbiterSend.data  = data_reg;
	assign arbiterSend.triggerSend = 0;
	
	assign arbiterSend.amount = '1;

endmodule