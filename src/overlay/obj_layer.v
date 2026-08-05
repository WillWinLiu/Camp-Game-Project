`timescale 1ns / 1ps
`include "hdmi/svo_defines.vh"
`include "game/game_defs.vh"

module obj_layer #(
	`SVO_DEFAULT_PARAMS,
	parameter MAX_OBJ       = 16,
	parameter LANE_BITS     = 4,
	parameter XOFF_BITS     = 4,
	parameter OBJ_TYPE_BITS = 3,
	parameter OBJ_Y_BITS    = 10
) (
	input clk,
	input resetn,

	// object state from game controller
	input [9:0] player_x,
	input [9:0] player_y,
	input       player_dir,
	input       skill_on,
	input [7:0] skill_timer,
	input [2:0] selected_character,

	input [MAX_OBJ              -1:0] obj_valid_bus,
	input [MAX_OBJ*LANE_BITS    -1:0] obj_lane_bus,
	input [MAX_OBJ*XOFF_BITS    -1:0] obj_xoff_bus,
	input [MAX_OBJ*OBJ_Y_BITS   -1:0] obj_ypos_bus,
	input [MAX_OBJ*OBJ_TYPE_BITS-1:0] obj_type_bus,

	// input stream from previous layer
	input in_axis_tvalid,
	output in_axis_tready,
	input [SVO_BITS_PER_PIXEL-1:0] in_axis_tdata,
	input [0:0] in_axis_tuser,

	// output stream to next layer
	output out_axis_tvalid,
	input out_axis_tready,
	output [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
	output [0:0] out_axis_tuser
);
`SVO_DECLS

localparam PLAYER_SRC_BITS = 5;
localparam PLAYER_SRC_ADDR_WIDTH = 11;         // {frame(1), src_y(5), src_x(5)} -> 2-frame walk sheet

localparam OBJ_ATLAS_ADDR_WIDTH = 11;      // {type(3), src_y(4), src_x(4)}
localparam OBJ_ATLAS_DEPTH = 2048;         // 8 type slots x 256, 7 used
localparam [7:0] TRANSPARENT_VAL = 8'h00;

reg [`SVO_XYBITS-1:0] hcursor;
reg [`SVO_XYBITS-1:0] vcursor;

reg obj_hit_d;
reg hit_player_d;
reg skill_on_d;
reg [SVO_BITS_PER_PIXEL-1:0] bg_rgb_d;
reg [0:0] tuser_d;
reg tvalid_d;

wire fire = in_axis_tvalid && in_axis_tready;
wire [`SVO_XYBITS-1:0] pixel_x = in_axis_tuser[0] ? 0 : hcursor;
wire [`SVO_XYBITS-1:0] pixel_y = in_axis_tuser[0] ? 0 : vcursor;

integer obj_i;
reg obj_hit;
reg [OBJ_TYPE_BITS-1:0] obj_type_now;
reg [4:0] obj_local_x;
reg [4:0] obj_local_y;
reg [10:0] scan_obj_x;
reg [9:0] scan_obj_ypos;
reg [9:0] scan_local_x;
reg [9:0] scan_local_y;
reg [5:0] scan_obj_w;
reg [5:0] scan_obj_h;

function [10:0] obj_x;
	input [LANE_BITS-1:0] lane;
	input [XOFF_BITS-1:0] xoff;
	begin obj_x = ({7'd0, lane} * 43 + {7'd0, xoff} * 2) - 11'd34; end
endfunction

always @(*) begin
	obj_hit = 0;
	obj_type_now = 0;
	obj_local_x = 0;
	obj_local_y = 0;
	scan_obj_x = 0;
	scan_obj_ypos = 0;
	scan_local_x = 0;
	scan_local_y = 0;
	scan_obj_w = 0;
	scan_obj_h = 0;

	for (obj_i = 0; obj_i < MAX_OBJ; obj_i = obj_i + 1) begin
		scan_obj_x = obj_x(
			obj_lane_bus[obj_i*LANE_BITS +: LANE_BITS],
			obj_xoff_bus[obj_i*XOFF_BITS +: XOFF_BITS]
		);
		scan_obj_ypos = obj_ypos_bus[obj_i*OBJ_Y_BITS +: OBJ_Y_BITS];
		scan_obj_w = 6'd32;
		scan_obj_h = 6'd32;

		// AABB hit test (using 11-bit signed arithmetic for pixel_x and scan_obj_x)
		if (!obj_hit && obj_valid_bus[obj_i] &&
			$signed({1'b0, pixel_x}) >= $signed({scan_obj_x[10] ? 1'b1 : 1'b0, scan_obj_x}) &&
			$signed({1'b0, pixel_x}) < $signed({scan_obj_x[10] ? 1'b1 : 1'b0, scan_obj_x}) + $signed({5'b00000, scan_obj_w}) &&
			pixel_y >= scan_obj_ypos && pixel_y < scan_obj_ypos + scan_obj_h) begin
			scan_local_x = pixel_x - scan_obj_x;
			scan_local_y = pixel_y - scan_obj_ypos;
			obj_hit = 1;
			obj_type_now = obj_type_bus[obj_i*OBJ_TYPE_BITS +: OBJ_TYPE_BITS];
			obj_local_x = scan_local_x[4:0];
			obj_local_y = scan_local_y[4:0];
		end
	end
end

// 16x16 slot object atlas mapping
wire [3:0] obj_src_x = obj_local_x[4:1];
wire [3:0] obj_src_y = obj_local_y[4:1];
// One atlas ROM holds every object sprite; the type picks its 256-entry slot, so
// no output mux is needed -- the registered read is already the selected pixel.
wire [OBJ_ATLAS_ADDR_WIDTH-1:0] obj_atlas_addr = {obj_type_now, obj_src_y, obj_src_x};
wire [7:0] obj_rgb;

wire hit_player = pixel_x >= player_x && pixel_x < player_x + `PLAYER_W &&
				  pixel_y >= player_y && pixel_y < player_y + `PLAYER_H;

// 16x16 -> 32x32 scaling by replicating pixels
wire [9:0] player_rel_x = pixel_x - player_x;
wire [9:0] player_rel_y = pixel_y - player_y;
wire [3:0] player_src_x = player_rel_x[4:1];
wire [3:0] player_src_y = player_rel_y[4:1];
wire [3:0] player_addr_x = player_dir ? player_src_x : (4'd15 - player_src_x);

wire [10:0] player_dino_addr = {selected_character, player_src_y, player_addr_x};

wire [1:0] shield_slot = (skill_timer[1:0] == 2'd3) ? 2'd0 : ((skill_timer[1:0] == 2'd2) ? 2'd1 : 2'd2);
wire [9:0] shield_addr = {shield_slot, player_src_y, player_src_x};
wire [7:0] shield_rgb;

wire [7:0] player_normal_rgb;
wire [7:0] player_skill_rgb;
wire [7:0] player_rgb = player_normal_rgb;

function [23:0] rgb323_to_bgr888;
	input [7:0] c;                 // [7:5]=R3 [4:3]=G2 [2:0]=B3
	reg [7:0] r;
	reg [7:0] g;
	reg [7:0] b;
	begin
		r = {c[7:5], c[7:5], c[7:6]};
		g = {c[4:3], c[4:3], c[4:3], c[4:3]};
		b = {c[2:0], c[2:0], c[2:1]};
		rgb323_to_bgr888 = {b, g, r};
	end
endfunction

reg [2:0] sel_char_d;

// If there is an object then just show it, otherwise show the background pixel
wire [SVO_BITS_PER_PIXEL-1:0] pxl_after_obj =
	obj_hit_d && obj_rgb != TRANSPARENT_VAL ?
	rgb323_to_bgr888(obj_rgb) : bg_rgb_d;

// If the player sprite or active shield is hit then show it, otherwise show whatever comes from obj layer
wire [SVO_BITS_PER_PIXEL-1:0] player_bgr = rgb323_to_bgr888(player_rgb);
wire [SVO_BITS_PER_PIXEL-1:0] shield_bgr = rgb323_to_bgr888(shield_rgb);

wire [SVO_BITS_PER_PIXEL-1:0] pxl_after_player =
	(hit_player_d && skill_on_d && shield_rgb != 8'h00) ? shield_bgr :
	(hit_player_d && player_rgb != 8'h00)               ? player_bgr : pxl_after_obj;

assign in_axis_tready  = out_axis_tready;
assign out_axis_tvalid = tvalid_d;
assign out_axis_tdata  = pxl_after_player;
assign out_axis_tuser  = tuser_d;

always @(posedge clk) begin
	if (!resetn) begin
		obj_hit_d <= 0;
		hit_player_d <= 0;
		skill_on_d <= 0;
		sel_char_d <= 0;
		bg_rgb_d <= 0;
		tuser_d <= 0;
		tvalid_d <= 0;
	end else if (out_axis_tready) begin
		tvalid_d <= in_axis_tvalid;
		if (fire) begin
			obj_hit_d <= obj_hit;
			hit_player_d <= hit_player;
			skill_on_d <= skill_on;
			sel_char_d <= selected_character;
			bg_rgb_d <= in_axis_tdata;
			tuser_d <= in_axis_tuser;
		end
	end
end

always @(posedge clk) begin
	if (!resetn) begin
		hcursor <= 0;
		vcursor <= 0;
	end else if (fire) begin
		if (in_axis_tuser[0]) begin
			hcursor <= 1;
			vcursor <= 0;
		end else if (hcursor == SVO_HOR_PIXELS - 1) begin
			hcursor <= 0;
			if (vcursor == SVO_VER_PIXELS - 1)
				vcursor <= 0;
			else
				vcursor <= vcursor + 1;
		end else begin
			hcursor <= hcursor + 1;
		end
	end
end

// Single object atlas ROM (RGB323): 8 type slots x 256 entries, addressed by
// {type, src_y, src_x}. Only slots 0-6 are populated by obj_atlas.mem.
rom #(
	.DATA_WIDTH(8),
	.ADDR_WIDTH(OBJ_ATLAS_ADDR_WIDTH),
	.DEPTH(OBJ_ATLAS_DEPTH),
	.INIT_FILE("src/assets/obj_atlas.mem")
) u_obj_atlas_rom (
	.clk(clk),
	.addr(obj_atlas_addr),
	.data(obj_rgb)
);

rom #(
	.DATA_WIDTH(8),
	.ADDR_WIDTH(11),
	.DEPTH(2048),
	.INIT_FILE("src/assets/dino_atlas.mem")
) u_player_right_rom (
	.clk(clk),
	.addr(player_dino_addr),
	.data(player_normal_rgb)
);

rom #(
	.DATA_WIDTH(8),
	.ADDR_WIDTH(10),
	.DEPTH(1024),
	.INIT_FILE("src/assets/shield_atlas.mem")
) u_shield_atlas_rom (
	.clk(clk),
	.addr(shield_addr),
	.data(shield_rgb)
);

endmodule
