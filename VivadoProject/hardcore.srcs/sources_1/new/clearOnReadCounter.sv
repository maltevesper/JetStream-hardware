module clearOnReadCounter #(
	parameter WIDTH = 4
)(
	input  logic clk,
	input  logic reset,
	input  logic increment,
	input  logic read,
	output logic [WIDTH-1:0] value
);

always_ff @(posedge clk) begin
	if(reset) begin
		value <= '0;
	end else begin
		if(read) begin
			value <= increment;
		end else begin
			value <= value + increment;
		end
	end 
end

endmodule