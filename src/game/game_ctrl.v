`timescale 1ns / 1ps
`include "game/game_defs.vh"

module game_ctrl #(
	parameter MAX_OBJ = 16,
	parameter LANE_BITS = 4,
	parameter XOFF_BITS = 4,
	parameter OBJ_TYPE_BITS = 3,
	parameter OBJ_Y_BITS = 10,
	parameter FALL_SPEED = 2,
	parameter SPAWN_PERIOD_FRAMES = 8,
	parameter PLAYER_HIT_TOP_PAD = 16,
	parameter PLAYER_START_X = 288,
	parameter PLAYER_SPEED_START = 8,
	parameter FPS = 60,
	parameter SKILL_CHARGE_MAX = 5,
	parameter SKILL_ENABLE = 1,
	parameter SKILL_DURATION = 0
)(
	input clk,
	input resetn,
	input frame_tick,

	input btn_left,
	input btn_right,
	input btn_start,
	input btn_skill,

	output reg [9:0] player_x,
	output reg [9:0] player_y,
	output reg [5:0] player_speed,
	output reg player_dir,

	output reg [MAX_OBJ              -1:0] obj_valid_bus,
	output reg [MAX_OBJ*LANE_BITS    -1:0] obj_lane_bus,
	output reg [MAX_OBJ*XOFF_BITS    -1:0] obj_xoff_bus,
	output reg [MAX_OBJ*OBJ_Y_BITS   -1:0] obj_ypos_bus,
	output reg [MAX_OBJ*OBJ_TYPE_BITS-1:0] obj_type_bus,

	output reg [9:0] score,
	output [11:0] score_bcd,
	output reg [11:0] high_score_bcd,
	output reg [2:0] skill_charge,
	output [7:0] skill_timer,
	output skill_on,
	output game_over,
	output menu_active,
	output [1:0] game_state,
	output reg [2:0] char_index,
	output reg [2:0] selected_character
);
localparam S_MENU = 2'd0;
localparam S_PLAY = 2'd1;
localparam S_OVER = 2'd2;

localparam TYPE_COIN_1 = 0;
localparam TYPE_COIN_3 = 1;
localparam TYPE_COIN_5 = 2;
localparam TYPE_MINUS3 = 3;
localparam TYPE_MINUS5 = 4;
localparam TYPE_TIME = 5;
localparam TYPE_CHARGE = 6;

localparam [9:0] SCREEN_W = 640;
localparam [9:0] OBJ_GROUND_Y = `UI_TOP - `OBJ_H;
localparam [9:0] PLAYER_MAX_X = SCREEN_W - `PLAYER_W;

reg [LANE_BITS    -1:0] obj_lane [0:MAX_OBJ-1];
reg [XOFF_BITS    -1:0] obj_xoff [0:MAX_OBJ-1];
reg [OBJ_TYPE_BITS-1:0] obj_type [0:MAX_OBJ-1];
reg [OBJ_Y_BITS   -1:0] obj_ypos [0:MAX_OBJ-1];
reg [4:0] obj_count;
reg [1:0] state;

reg [7:0] frame_cnt;
reg [7:0] spawn_cnt;
reg [2:0] score_cnt;
reg signed [6:0] jump_vy;
localparam [9:0] PLAYER_GROUND_Y = `PLAYER_Y; // 352
localparam signed [6:0] JUMP_IMPULSE = -7'sd12;
localparam signed [6:0] GRAVITY = 7'sd1;

reg btn_start_q, btn_left_q, btn_right_q, btn_skill_q;
reg [7:0] spawn_period;
reg [5:0] menu_btn_timer;
reg [1:0] shield_hp;
reg [9:0] next_shield_score;

wire any_start_btn  = btn_start || btn_skill;
wire btn_start_rise = any_start_btn && !btn_start_q;
wire btn_left_rise  = btn_left  && !btn_left_q;
wire btn_right_rise = btn_right && !btn_right_q;
wire btn_skill_rise = btn_skill && !btn_skill_q;

assign skill_on = (shield_hp > 0);
assign skill_timer = {6'b0, shield_hp};
wire skill_start;
wire skill_btn_active = btn_skill && state == S_PLAY;
wire can_left = player_x > player_speed;
wire can_right = player_x + player_speed < PLAYER_MAX_X;

wire [10:0] spawn_data;
wire spawn_fifo_empty;
wire obj_has_room = obj_count < MAX_OBJ;
wire remove_valid;
wire spawn_pop = frame_tick && state == S_PLAY &&
				  spawn_cnt == 0 && !spawn_fifo_empty &&
				  (obj_has_room || remove_valid);
wire game_step = frame_tick && state == S_PLAY;
wire timer_tick = frame_cnt == FPS - 1;
wire sec_tick = game_step && timer_tick;

assign game_over   = (state == S_OVER);
assign menu_active = (state == S_MENU);
assign game_state  = state;



spawn_queue u_spawn_queue (
	.clk(clk),
	.resetn(resetn),
	.enable(state == S_PLAY),
	.pop(spawn_pop),
	.spawn_data(spawn_data),
	.empty(spawn_fifo_empty)
);

wire [LANE_BITS-1:0] spawn_lane_raw = spawn_data[10:7];
wire [XOFF_BITS-1:0] spawn_xoff_raw = spawn_data[6:3];
wire [OBJ_TYPE_BITS-1:0] spawn_type_raw = spawn_data[2:0];
wire [LANE_BITS-1:0] spawn_lane;
wire [XOFF_BITS-1:0] spawn_xoff;
wire [OBJ_TYPE_BITS-1:0] spawn_type;

spawn_postprocess #(
	.LANE_BITS(LANE_BITS),
	.XOFF_BITS(XOFF_BITS),
	.OBJ_TYPE_BITS(OBJ_TYPE_BITS)
) u_spawn_postprocess (
	.clk(clk),
	.resetn(resetn),
	.fire(spawn_pop),
	.raw_lane(spawn_lane_raw),
	.raw_xoff(spawn_xoff_raw),
	.raw_type(spawn_type_raw),
	.out_lane(spawn_lane),
	.out_xoff(spawn_xoff),
	.out_type(spawn_type)
);

integer hit_i;
reg hit_valid;
reg [4:0] hit_idx;
reg [10:0] hit_obj_x;
wire [10:0] hit_player_l = player_x;
wire [10:0] hit_player_r = player_x + `PLAYER_W;
wire [10:0] hit_player_t = player_y + PLAYER_HIT_TOP_PAD;
wire [10:0] hit_player_b = player_y + `PLAYER_H;

function [10:0] obj_x;
	input [LANE_BITS-1:0] lane;
	input [XOFF_BITS-1:0] xoff;
	begin obj_x = ({7'd0, lane} * 43 + {7'd0, xoff} * 2) - 11'd34; end
endfunction

always @(*) begin
	hit_valid = 0;
	hit_idx = 0;
	hit_obj_x = 0;

	for (hit_i = 0; hit_i < MAX_OBJ; hit_i = hit_i + 1) begin
		hit_obj_x = obj_x(obj_lane[hit_i], obj_xoff[hit_i]);
		// Rule 2 & 3: Only Cactus (Type 0) collides with player. Meteorite (Type 1) is in background (non-colliding).
		if (!hit_valid && hit_i < obj_count &&
			obj_type[hit_i] == 1'b0 &&
			hit_player_l < hit_obj_x + `OBJ_W &&
			hit_player_r > hit_obj_x &&
			hit_player_t < obj_ypos[hit_i] + `OBJ_H &&
			hit_player_b > obj_ypos[hit_i]) begin
			hit_valid = 1;
			hit_idx = hit_i[4:0];
		end
	end
end

// Out of bounds test: Cactus (Type 0) reaches left edge OR Meteorite (Type 1) falls past bottom edge (Y >= 440)
reg offscreen_valid;
reg [4:0] offscreen_idx;
integer off_i;
always @(*) begin
	offscreen_valid = 0;
	offscreen_idx = 0;
	for (off_i = 0; off_i < MAX_OBJ; off_i = off_i + 1) begin
		if (!offscreen_valid && off_i < obj_count) begin
			if (obj_type[off_i] == 1'b0 && obj_lane[off_i] == 0 && obj_xoff[off_i] == 0) begin
				offscreen_valid = 1;
				offscreen_idx = off_i[4:0];
			end else if (obj_type[off_i] == 1'b1 && obj_ypos[off_i] >= 10'd440) begin
				offscreen_valid = 1;
				offscreen_idx = off_i[4:0];
			end
		end
	end
end

assign remove_valid = (hit_valid && shield_hp > 0) || offscreen_valid;
wire [4:0] remove_idx = (hit_valid && shield_hp > 0) ? hit_idx : offscreen_idx;

reg [9:0] next_score;
reg [2:0] next_charge;
reg signed [5:0] score_delta;
reg signed [6:0] score_delta_eff;
reg signed [10:0] score_sum;
wire [9:0] final_score = hit_valid ? next_score : score;

always @(*) begin
	next_score = score;
	next_charge = skill_charge;
	score_delta = 0;
	score_delta_eff = 0;
	score_sum = score;

	// Rule 1: Neither Cacti nor Meteorites give points!
	if (hit_valid) begin
		score_delta = 0; // 0 points given on obstacle collision
	end
end



wire [11:0] final_score_12 = {2'b00, final_score};

bin2bcd #(
	.BIN_BITS(12)
) u_score_bcd (
	.bin(final_score_12),
	.bcd(score_bcd)
);

integer pack_i;

always @(*) begin
	obj_valid_bus = 0;
	obj_lane_bus = 0;
	obj_xoff_bus = 0;
	obj_ypos_bus = 0;
	obj_type_bus = 0;

	for (pack_i = 0; pack_i < MAX_OBJ; pack_i = pack_i + 1) begin
		if (pack_i < obj_count) begin
			obj_valid_bus[pack_i] = 1;
			obj_lane_bus[pack_i*LANE_BITS     +: LANE_BITS]     = obj_lane[pack_i];
			obj_xoff_bus[pack_i*XOFF_BITS     +: XOFF_BITS]     = obj_xoff[pack_i];
			obj_ypos_bus[pack_i*OBJ_Y_BITS    +: OBJ_Y_BITS]    = obj_ypos[pack_i];
			obj_type_bus[pack_i*OBJ_TYPE_BITS +: OBJ_TYPE_BITS] = obj_type[pack_i];
		end
	end
end

integer i;

always @(posedge clk) begin
	if (!resetn) begin
		player_x <= PLAYER_START_X;
		player_speed <= PLAYER_SPEED_START;
		player_dir <= 1;
		spawn_period <= SPAWN_PERIOD_FRAMES;
		obj_count <= 0;
		score <= 0;
		score_cnt <= 0;
		high_score_bcd <= 12'h000;
		skill_charge <= 0;
		state <= S_MENU;
		char_index <= 0;
		selected_character <= 0;
		frame_cnt <= 0;
		spawn_cnt <= SPAWN_PERIOD_FRAMES;
		btn_start_q <= 0;
		btn_left_q <= 0;
		btn_right_q <= 0;

		for (i = 0; i < MAX_OBJ; i = i + 1) begin
			obj_lane[i] <= 0;
			obj_xoff[i] <= 0;
			obj_ypos[i] <= 0;
			obj_type[i] <= 0;
		end
	end else begin
		btn_start_q <= any_start_btn;
		btn_left_q  <= btn_left;
		btn_right_q <= btn_right;

		if (frame_tick && menu_btn_timer > 0)
			menu_btn_timer <= menu_btn_timer - 1;

		if (state == S_MENU) begin
			if (menu_btn_timer == 0) begin
				if (btn_left_rise || (btn_left && frame_tick)) begin
					if (char_index > 0) begin
						char_index <= char_index - 1;
						menu_btn_timer <= 15;
					end
				end else if (btn_right_rise || (btn_right && frame_tick)) begin
					if (char_index < 4) begin
						char_index <= char_index + 1;
						menu_btn_timer <= 15;
					end
				end else if (btn_start_rise || (any_start_btn && frame_tick)) begin
					state <= S_PLAY;
					selected_character <= char_index;
					player_x <= 10'd100;
					player_y <= PLAYER_GROUND_Y;
					jump_vy <= 0;
					player_speed <= PLAYER_SPEED_START;
					player_dir <= 1;
					spawn_period <= SPAWN_PERIOD_FRAMES;
					obj_count <= 0;
					score <= 0;
					score_cnt <= 0;
					skill_charge <= 0;
					shield_hp <= 0;
					next_shield_score <= 10'd50;
					frame_cnt <= 0;
					spawn_cnt <= SPAWN_PERIOD_FRAMES;

					for (i = 0; i < MAX_OBJ; i = i + 1) begin
						obj_lane[i] <= 0;
						obj_xoff[i] <= 0;
						obj_ypos[i] <= 0;
						obj_type[i] <= 0;
					end
				end
			end
		end else if (state == S_OVER) begin
			if (btn_start_rise || (any_start_btn && frame_tick)) begin
				state <= S_MENU;
				menu_btn_timer <= 15;
			end
		end else begin
			if (frame_tick && state == S_PLAY) begin
					btn_start_q <= any_start_btn;
					btn_left_q  <= btn_left;
					btn_right_q <= btn_right;
					btn_skill_q <= btn_skill;

					// Equip 3-Hit Shield when Button 3 (btn_skill) is pressed & charge available
					if (btn_skill_rise && skill_charge > 0 && shield_hp == 0) begin
						skill_charge <= skill_charge - 1;
						shield_hp <= 2'd3;
					end

					// Earn 1 Shield Charge for every 50 score (Max 3 stored charges!)
					if (score >= next_shield_score) begin
						if (skill_charge < 3'd3) begin
							skill_charge <= skill_charge + 1;
						end
						next_shield_score <= next_shield_score + 10'd50;
					end

					if (hit_valid) begin
						if (shield_hp > 0) begin
							shield_hp <= shield_hp - 1; // Absorbs hit & passes through!
						end else begin
							state <= S_OVER;
							if (score_bcd > high_score_bcd) begin
								high_score_bcd <= score_bcd;
							end
						end
					end

					// Player Control: Button 1 (btn_left) Jump higher, Button 2 (btn_right) Fast-Fall to ground faster
					player_x <= 10'd100;
					player_dir <= 1;

					if (player_y == PLAYER_GROUND_Y) begin
						if (btn_left) begin
							jump_vy <= JUMP_IMPULSE;
							player_y <= PLAYER_GROUND_Y - 12;
						end else begin
							jump_vy <= 0;
							player_y <= PLAYER_GROUND_Y;
						end
					end else begin
						// Slower, floaty descent when falling (apply gravity every alternate frame, or fast-fall if Button 2 pressed)
						if ($signed({1'b0, player_y}) + jump_vy + (btn_right ? 7'sd4 : (frame_cnt[0] ? GRAVITY : 7'sd0)) >= $signed({1'b0, PLAYER_GROUND_Y})) begin
							player_y <= PLAYER_GROUND_Y;
							jump_vy <= 0;
						end else begin
							player_y <= $signed({1'b0, player_y}) + jump_vy;
							jump_vy <= jump_vy + (btn_right ? 7'sd4 : (frame_cnt[0] ? GRAVITY : 7'sd0));
						end
					end

					// Object movement (Cactus speed increased: moves 2 units per frame across floor)
					if (remove_valid) begin
						for (i = 0; i < MAX_OBJ-1; i = i + 1) begin
							if (i < obj_count - 1) begin
								if (i < remove_idx) begin
									if (obj_type[i] == 1'b0) begin
										if ({obj_lane[i], obj_xoff[i]} >= 4) begin
											obj_lane[i] <= ({obj_lane[i], obj_xoff[i]} - 3'd4) >> 4;
											obj_xoff[i] <= ({obj_lane[i], obj_xoff[i]} - 3'd4) & 4'hF;
										end else begin
											obj_lane[i] <= 0;
											obj_xoff[i] <= 0;
										end
									end else begin
										obj_ypos[i] <= obj_ypos[i] + 3;
										if ({obj_lane[i], obj_xoff[i]} >= 1) begin
											obj_lane[i] <= ({obj_lane[i], obj_xoff[i]} - 2'd1) >> 4;
											obj_xoff[i] <= ({obj_lane[i], obj_xoff[i]} - 2'd1) & 4'hF;
										end else begin
											obj_lane[i] <= 0;
											obj_xoff[i] <= 0;
										end
									end
								end else begin
									obj_lane[i] <= obj_lane[i+1];
									obj_xoff[i] <= obj_xoff[i+1];
									obj_type[i] <= obj_type[i+1];
									obj_ypos[i] <= obj_ypos[i+1];
								end
							end
						end

						if (spawn_pop) begin
							obj_lane[obj_count - 1] <= (spawn_type == 1'b0) ? 4'hF : spawn_lane;
							obj_xoff[obj_count - 1] <= (spawn_type == 1'b0) ? 4'hF : spawn_xoff;
							obj_type[obj_count - 1] <= spawn_type;
							obj_ypos[obj_count - 1] <= (spawn_type == 1'b0) ? 10'd384 : 10'd0;
							obj_count <= obj_count;
						end else begin
							obj_count <= obj_count - 1;
						end
					end else begin
						for (i = 0; i < MAX_OBJ; i = i + 1) begin
							if (i < obj_count) begin
								if (obj_type[i] == 1'b0) begin
									if ({obj_lane[i], obj_xoff[i]} >= 4) begin
										obj_lane[i] <= ({obj_lane[i], obj_xoff[i]} - 3'd4) >> 4;
										obj_xoff[i] <= ({obj_lane[i], obj_xoff[i]} - 3'd4) & 4'hF;
									end else begin
										obj_lane[i] <= 0;
										obj_xoff[i] <= 0;
									end
								end else begin
									obj_ypos[i] <= obj_ypos[i] + 3; // Fall straight down
									if ({obj_lane[i], obj_xoff[i]} >= 1) begin
										obj_lane[i] <= ({obj_lane[i], obj_xoff[i]} - 2'd1) >> 4;
										obj_xoff[i] <= ({obj_lane[i], obj_xoff[i]} - 2'd1) & 4'hF;
									end else begin
										obj_lane[i] <= 0;
										obj_xoff[i] <= 0;
									end
								end
							end
						end

						if (spawn_pop) begin
							obj_lane[obj_count] <= (spawn_type == 1'b0) ? 4'hF : spawn_lane;
							obj_xoff[obj_count] <= (spawn_type == 1'b0) ? 4'hF : spawn_xoff;
							obj_type[obj_count] <= spawn_type;
							obj_ypos[obj_count] <= (spawn_type == 1'b0) ? 10'd384 : 10'd0;
							obj_count <= obj_count + 1;
						end
					end

					if (spawn_pop)
						spawn_cnt <= spawn_period - 1;
					else if (spawn_cnt != 0)
						spawn_cnt <= spawn_cnt - 1;

					// Score increment logic (1 point every 6 frames)
					if (score_cnt == 5) begin
						score_cnt <= 0;
						if (score < 10'd999) begin
							score <= score + 1;
						end
					end else begin
						score_cnt <= score_cnt + 1;
					end

					// Live high score update (surpass the high score with current score)
					if (score_bcd > high_score_bcd) begin
						high_score_bcd <= score_bcd;
					end

					// Keep frame_cnt running (for gravity and sec_tick)
					if (timer_tick) begin
						frame_cnt <= 0;
					end else begin
						frame_cnt <= frame_cnt + 1;
					end
				end
		end

		if (SKILL_ENABLE && skill_start)
			skill_charge <= 0;
	end
end
endmodule
