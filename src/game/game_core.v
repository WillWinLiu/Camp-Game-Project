`timescale 1ns / 1ps
`include "hdmi/svo_defines.vh"

module game_core #(
	parameter SVO_MODE             =   "640x480V",
	parameter SVO_FRAMERATE        =   60,
	parameter SVO_BITS_PER_PIXEL  
	 =   24,
	parameter SVO_BITS_PER_RED     =    8,
	parameter SVO_BITS_PER_GREEN   =    8,
	parameter SVO_BITS_PER_BLUE    =    8,
	parameter SVO_BITS_PER_ALPHA   =    0
) (
	input clk,
	input resetn,

	input btn_left,
	input btn_right,
	input btn_start,
	input btn_skill,

	output out_axis_tvalid,
	input out_axis_tready,
	output [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
	output [0:0] out_axis_tuser
);
localparam MAX_OBJ = 8;
localparam LANE_BITS = 4;
localparam XOFF_BITS = 4;
localparam OBJ_TYPE_BITS = 3;
localparam OBJ_Y_BITS = 10;

wire bg_tvalid;
wire bg_tready;
wire [SVO_BITS_PER_PIXEL-1:0] bg_tdata;
wire [0:0] bg_tuser;

wire obj_tvalid;
wire obj_tready;
wire [SVO_BITS_PER_PIXEL-1:0] obj_tdata;
wire [0:0] obj_tuser;

wire ui_tvalid;
wire ui_tready;
wire [SVO_BITS_PER_PIXEL-1:0] ui_tdata;
wire [0:0] ui_tuser;

wire menu_tvalid;
wire menu_tready;
wire [SVO_BITS_PER_PIXEL-1:0] menu_tdata;
wire [0:0] menu_tuser;

wire frame_tick;
wire [9:0] player_x;
wire [9:0] player_y;
wire player_dir;
wire [MAX_OBJ              -1:0] obj_valid_bus;
wire [MAX_OBJ*LANE_BITS    -1:0] obj_lane_bus;
wire [MAX_OBJ*XOFF_BITS    -1:0] obj_xoff_bus;
wire [MAX_OBJ*OBJ_Y_BITS   -1:0] obj_ypos_bus;
wire [MAX_OBJ*OBJ_TYPE_BITS-1:0] obj_type_bus;
wire [9:0] score;
wire [11:0] score_bcd;
wire [11:0] high_score_bcd;
wire [2:0] skill_charge;
wire [7:0] skill_timer;
wire skill_on;
wire game_over;
wire menu_active;
wire [1:0] game_state;
wire [2:0] char_index;
wire [2:0] selected_character;

// Frame start signal
assign frame_tick = bg_tvalid && bg_tready && bg_tuser[0];

game_ctrl #(
	.MAX_OBJ(MAX_OBJ),
	.LANE_BITS(LANE_BITS),
	.XOFF_BITS(XOFF_BITS),
	.OBJ_TYPE_BITS(OBJ_TYPE_BITS),
	.OBJ_Y_BITS(OBJ_Y_BITS)
) u_game_ctrl (
	.clk(clk),
	.resetn(resetn),
	.frame_tick(frame_tick),

	.btn_left(btn_left),
	.btn_right(btn_right),
	.btn_start(btn_start),
	.btn_skill(btn_skill),

	.player_x(player_x),
	.player_y(player_y),
	.player_dir(player_dir),

	.obj_valid_bus(obj_valid_bus),
	.obj_lane_bus(obj_lane_bus),
	.obj_xoff_bus(obj_xoff_bus),
	.obj_ypos_bus(obj_ypos_bus),
	.obj_type_bus(obj_type_bus),

	.score(score),
	.score_bcd(score_bcd),
	.high_score_bcd(high_score_bcd),
	.skill_charge(skill_charge),
	.skill_timer(skill_timer),
	.skill_on(skill_on),
	.game_over(game_over),
	.menu_active(menu_active),
	.game_state(game_state),
	.char_index(char_index),
	.selected_character(selected_character)
);

bg_layer #(
	`SVO_PASS_PARAMS,
	.BG_TILE_FILE("src/assets/background.mem")
) u_bg_layer (
	.clk(clk),
	.resetn(resetn),

	.out_axis_tvalid(bg_tvalid),
	.out_axis_tready(bg_tready),
	.out_axis_tdata(bg_tdata),
	.out_axis_tuser(bg_tuser)
);

obj_layer #(
	`SVO_PASS_PARAMS,
	.MAX_OBJ(MAX_OBJ),
	.LANE_BITS(LANE_BITS),
	.XOFF_BITS(XOFF_BITS),
	.OBJ_TYPE_BITS(OBJ_TYPE_BITS),
	.OBJ_Y_BITS(OBJ_Y_BITS)
) u_obj_layer (
	.clk(clk),
	.resetn(resetn),

	.player_x(player_x),
	.player_y(player_y),
	.player_dir(player_dir),
	.skill_on(skill_on),
	.skill_timer(skill_timer),
	.selected_character(selected_character),
	.obj_valid_bus(obj_valid_bus),
	.obj_lane_bus(obj_lane_bus),
	.obj_xoff_bus(obj_xoff_bus),
	.obj_ypos_bus(obj_ypos_bus),
	.obj_type_bus(obj_type_bus),

	.in_axis_tvalid(bg_tvalid),
	.in_axis_tready(bg_tready),
	.in_axis_tdata(bg_tdata),
	.in_axis_tuser(bg_tuser),

	.out_axis_tvalid(obj_tvalid),
	.out_axis_tready(obj_tready),
	.out_axis_tdata(obj_tdata),
	.out_axis_tuser(obj_tuser)
);

ui_layer #(
	`SVO_PASS_PARAMS
) u_ui_layer (
	.clk(clk),
	.resetn(resetn),

	.score_bcd(score_bcd),
	.high_score_bcd(high_score_bcd),
	.skill_charge(skill_charge),
	.skill_timer(skill_timer),
	.game_over(game_over),
	.btn_left(btn_left),
	.btn_right(btn_right),

	.in_axis_tvalid(obj_tvalid),
	.in_axis_tready(obj_tready),
	.in_axis_tdata(obj_tdata),
	.in_axis_tuser(obj_tuser),

	.out_axis_tvalid(ui_tvalid),
	.out_axis_tready(ui_tready),
	.out_axis_tdata(ui_tdata),
	.out_axis_tuser(ui_tuser)
);

char_menu #(
	`SVO_PASS_PARAMS
) u_char_menu (
	.clk(clk),
	.resetn(resetn),

	.show(menu_active),
	.char_index(char_index),

	.in_axis_tvalid(ui_tvalid),
	.in_axis_tready(ui_tready),
	.in_axis_tdata(ui_tdata),
	.in_axis_tuser(ui_tuser),

	.out_axis_tvalid(menu_tvalid),
	.out_axis_tready(menu_tready),
	.out_axis_tdata(menu_tdata),
	.out_axis_tuser(menu_tuser)
);

res_overlay #(
	`SVO_PASS_PARAMS
) u_res_overlay (
	.clk(clk),
	.resetn(resetn),

	.show(game_over),
	.score_bcd(score_bcd),
	.high_score_bcd(high_score_bcd),

	.in_axis_tvalid(menu_tvalid),
	.in_axis_tready(menu_tready),
	.in_axis_tdata(menu_tdata),
	.in_axis_tuser(menu_tuser),

	.out_axis_tvalid(out_axis_tvalid),
	.out_axis_tready(out_axis_tready),
	.out_axis_tdata(out_axis_tdata),
	.out_axis_tuser(out_axis_tuser)
);
endmodule
