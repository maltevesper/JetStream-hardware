module sink #(
	parameter logic DEBUG = 0
)(
	input logic clk,
	input logic reset,
	Adapter2Arbiter_receive.adapter arbiterReceive
);
	
	assign arbiterReceive.amount = '1;
	
	
	generate
	if(DEBUG) begin
		(* mark_debug = "true" *) logic [pcieInterfaces::INTERFACEWIDTH-1:0] data_reg;
		
		always_ff @(posedge clk) begin : BUFFER	
			if(reset) begin
				data_reg = '0;
			end else begin
				if(arbiterReceive.valid) begin
					data_reg <= arbiterReceive.data;
				end
			end
		end
	end
	endgenerate 
endmodule
