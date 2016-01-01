/*
 * Backwards parametrization.
 * 
 * Since system verilog does not allow to constrain a parameterized interface in a modules portlist
 * we actually use the data specified on the interface to infer the size of the ram.
 * Akward. DOES NOT WORK YET
 */

interface simpleDualRamIF # (
	parameter WIDTH = 32,
	parameter DEPTH = 64
);
	logic [WIDTH-1:0] dataIn;
	logic [WIDTH-1:0] dataOut;
	logic write;
	logic read;
	logic [$clog2(DEPTH)-1:0] writeAddress;
	logic [$clog2(DEPTH)-1:0] readAddress;
	
	modport core(
		input  dataIn,
		output dataOut,
		input  write,
		input  read,
		input  writeAddress,
		input  readAddress
	);
	
	modport userLogic(
		output dataIn,
		input  dataOut,
		output write,
		output read,
		output writeAddress,
		output readAddress
	);

endinterface

//package libram;

module simpleDualRam # (
	parameter WIDTH = 32,
	parameter DEPTH = 64
)(
	input logic clk,
	simpleDualRamIF.userLogic port
);
	//reg [port.WIDTH-1:0] outputBuffer;
	//reg [port.WIDTH-1:0] memory[port.DEPTH-1:0];
	reg [WIDTH-1:0] memory[DEPTH-1:0];
	
	always @(posedge clk)
	begin
		if(port.write) begin
			memory[port.writeAddress] <= port.dataIn;
		end
	end
	
	always @(posedge clk)
	begin
		if(port.read) begin
			port.dataOut <= memory[port.readAddress];
		end
	end
endmodule

/*module simpleDualRam #(parameter WIDTH=32, simpleDualRamIF t=simpleDualRamIF #(WIDTH)) (
	logic clk,
	t port
);
	
	$error("Interface width %d\n", port.width);
	//assert ($width(port.dataIn)) else $error("It's gone wrong");
	
endmodule*/

//endpackage