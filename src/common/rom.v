`timescale 1ns / 1ps

module rom #(
	parameter DATA_WIDTH = 16,
	parameter DEPTH = 1024,
	parameter ADDR_WIDTH = $clog2(DEPTH),
	parameter INIT_FILE = "src/assets/background.mem"
)(
	input clk,
	input [ADDR_WIDTH-1:0] addr,
	output reg [DATA_WIDTH-1:0] data
);
(* syn_ramstyle = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

initial begin
	$readmemh(INIT_FILE, mem);
end

always @(posedge clk) begin
	data <= mem[addr];
end
endmodule
