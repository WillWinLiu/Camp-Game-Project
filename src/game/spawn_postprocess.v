`timescale 1ns / 1ps

module spawn_postprocess #(
	parameter LANE_BITS = 4,
	parameter XOFF_BITS = 4,
	parameter OBJ_TYPE_BITS = 3
)(
	input clk,
	input resetn,
	input fire,

	input [LANE_BITS-1:0] raw_lane,
	input [XOFF_BITS-1:0] raw_xoff,
	input [OBJ_TYPE_BITS-1:0] raw_type,

	output [LANE_BITS-1:0] out_lane,
	output [XOFF_BITS-1:0] out_xoff,
	output [OBJ_TYPE_BITS-1:0] out_type
);

assign out_lane = raw_lane;
assign out_xoff = raw_xoff;
assign out_type = raw_type;

endmodule
