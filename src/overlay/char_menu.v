`timescale 1ns / 1ps
`include "hdmi/svo_defines.vh"

module char_menu #(
	`SVO_DEFAULT_PARAMS,
	parameter NUM_CHARS = 5
) (
	input wire clk,
	input wire resetn,

	input wire show,              // 1 = Menu Active, 0 = In Game
	input wire [2:0] char_index,  // Selected character index (0 to NUM_CHARS-1)

	// SVO stream input
	input wire in_axis_tvalid,
	output wire in_axis_tready,
	input wire [SVO_BITS_PER_PIXEL-1:0] in_axis_tdata,
	input wire [0:0] in_axis_tuser,

	// SVO stream output
	output wire out_axis_tvalid,
	input wire out_axis_tready,
	output wire [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
	output wire [0:0] out_axis_tuser
);
`SVO_DECLS

// Menu Colors
localparam [23:0] COLOR_WHITE = 24'hFFFFFF; // Menu White Background
localparam [23:0] COLOR_ARROW = 24'h2080FF; // Vibrant blue selection arrows

// Centered Character Sprite Box (128x128 px centered at X=320, Y=260)
localparam [9:0] CHAR_SQUARE_X0 = 10'd256;
localparam [9:0] CHAR_SQUARE_X1 = 10'd384;
localparam [9:0] CHAR_SQUARE_Y0 = 10'd196;
localparam [9:0] CHAR_SQUARE_Y1 = 10'd324;

// Arrow Bounding Ranges (Enlarged 40x40 arrows)
localparam [9:0] ARROW_Y_CENTER = 10'd260;
localparam [9:0] ARROW_HALF_H   = 10'd24;
localparam [9:0] ARROW_W        = 10'd24;

// Left Arrow X range: [192, 216]
localparam [9:0] L_ARROW_X0 = 10'd192;
localparam [9:0] L_ARROW_X1 = 10'd216;

// Right Arrow X range: [424, 448]
localparam [9:0] R_ARROW_X0 = 10'd424;
localparam [9:0] R_ARROW_X1 = 10'd448;

// "DINO RUNNER" Title Positioning: X in [166, 474), Y in [80, 108) (308px wide, 28px tall)
localparam [9:0] TITLE_X0 = 10'd166;
localparam [9:0] TITLE_X1 = 10'd474;
localparam [9:0] TITLE_Y0 = 10'd80;
localparam [9:0] TITLE_Y1 = 10'd108;

reg [`SVO_XYBITS-1:0] hcursor;
reg [`SVO_XYBITS-1:0] vcursor;

wire fire = in_axis_tvalid && in_axis_tready;
wire [`SVO_XYBITS-1:0] pixel_x = in_axis_tuser[0] ? 0 : hcursor;
wire [`SVO_XYBITS-1:0] pixel_y = in_axis_tuser[0] ? 0 : vcursor;

// Dynamic Arrow Availability Rules
wire can_go_left  = (char_index > 0);
wire can_go_right = (char_index < NUM_CHARS - 1);

// Character Sprite Bounding Box Test
wire in_char_square = (pixel_x >= CHAR_SQUARE_X0 && pixel_x < CHAR_SQUARE_X1 &&
                       pixel_y >= CHAR_SQUARE_Y0 && pixel_y < CHAR_SQUARE_Y1);

// Local 32x32 Sprite Address (scaled 4x up to 128x128 box)
wire [6:0] rel_x = pixel_x - CHAR_SQUARE_X0;
wire [6:0] rel_y = pixel_y - CHAR_SQUARE_Y0;
wire [3:0] sprite_x = rel_x[6:3];
wire [3:0] sprite_y = rel_y[6:3];

// 16x16 sprite atlas address: {char_index[2:0], sprite_y[3:0], sprite_x[3:0]} (11 bits address, 2048 entries)
wire [10:0] dino_atlas_addr = {char_index, sprite_y, sprite_x};
wire [7:0] dino_rgb;

// Single Unified 8,192-Entry ROM for all Dinosaur Menu Sprites
rom #(
	.DATA_WIDTH(8),
	.ADDR_WIDTH(11),
	.DEPTH(2048),
	.INIT_FILE("src/assets/dino_atlas.mem")
) u_dino_atlas_rom (
	.clk(clk),
	.addr(dino_atlas_addr),
	.data(dino_rgb)
);

// Procedural Arrow Geometry Functions (Flipped Horizontally)
function is_left_arrow_pixel;
	input [`SVO_XYBITS-1:0] px, py;
	reg signed [10:0] dy, dx;
	begin
		is_left_arrow_pixel = 0;
		if (px >= L_ARROW_X0 && px < L_ARROW_X1 &&
		    py >= ARROW_Y_CENTER - ARROW_HALF_H && py < ARROW_Y_CENTER + ARROW_HALF_H) begin
			dy = (py > ARROW_Y_CENTER) ? (py - ARROW_Y_CENTER) : (ARROW_Y_CENTER - py);
			dx = px - L_ARROW_X0;
			if (dy <= (dx * ARROW_HALF_H / ARROW_W)) is_left_arrow_pixel = 1;
		end
	end
endfunction

function is_right_arrow_pixel;
	input [`SVO_XYBITS-1:0] px, py;
	reg signed [10:0] dy, dx;
	begin
		is_right_arrow_pixel = 0;
		if (px >= R_ARROW_X0 && px < R_ARROW_X1 &&
		    py >= ARROW_Y_CENTER - ARROW_HALF_H && py < ARROW_Y_CENTER + ARROW_HALF_H) begin
			dy = (py > ARROW_Y_CENTER) ? (py - ARROW_Y_CENTER) : (ARROW_Y_CENTER - py);
			dx = R_ARROW_X1 - px;
			if (dy <= (dx * ARROW_HALF_H / ARROW_W)) is_right_arrow_pixel = 1;
		end
	end
endfunction

// --- Colorful "DINO RUNNER" Title Decoder ---
wire in_title_box = (pixel_x >= TITLE_X0 && pixel_x < TITLE_X1 &&
                     pixel_y >= TITLE_Y0 && pixel_y < TITLE_Y1);

wire [8:0] title_rel_x = pixel_x - TITLE_X0;
wire [4:0] title_rel_y = pixel_y - TITLE_Y0;

// 11 slots (10 chars + 1 space): each char slot is 28px wide (20px char + 8px space)
wire [3:0] title_char_idx = title_rel_x / 28;
wire [4:0] char_local_x   = (title_rel_x % 28);
wire [2:0] font_x         = char_local_x[4:2]; // scale 4x (0..4)
wire [2:0] font_y         = title_rel_y[4:2];  // scale 4x (0..6)

function is_font_pixel;
	input [3:0] char_idx;
	input [2:0] fx, fy;
	reg [4:0] row_bits;
	begin
		is_font_pixel = 0;
		if (fx < 5 && fy < 7) begin
			case (char_idx)
				4'd0: // D
					case (fy)
						3'd0: row_bits = 5'b11110;
						3'd1: row_bits = 5'b10001;
						3'd2: row_bits = 5'b10001;
						3'd3: row_bits = 5'b10001;
						3'd4: row_bits = 5'b10001;
						3'd5: row_bits = 5'b10001;
						3'd6: row_bits = 5'b11110;
						default: row_bits = 0;
					endcase
				4'd1: // I
					case (fy)
						3'd0: row_bits = 5'b11111;
						3'd1: row_bits = 5'b00100;
						3'd2: row_bits = 5'b00100;
						3'd3: row_bits = 5'b00100;
						3'd4: row_bits = 5'b00100;
						3'd5: row_bits = 5'b00100;
						3'd6: row_bits = 5'b11111;
						default: row_bits = 0;
					endcase
				4'd2: // N
					case (fy)
						3'd0: row_bits = 5'b10001;
						3'd1: row_bits = 5'b11001;
						3'd2: row_bits = 5'b10101;
						3'd3: row_bits = 5'b10011;
						3'd4: row_bits = 5'b10001;
						3'd5: row_bits = 5'b10001;
						3'd6: row_bits = 5'b10001;
						default: row_bits = 0;
					endcase
				4'd3: // O
					case (fy)
						3'd0: row_bits = 5'b01110;
						3'd1: row_bits = 5'b10001;
						3'd2: row_bits = 5'b10001;
						3'd3: row_bits = 5'b10001;
						3'd4: row_bits = 5'b10001;
						3'd5: row_bits = 5'b10001;
						3'd6: row_bits = 5'b01110;
						default: row_bits = 0;
					endcase
				4'd4: row_bits = 5'b00000; // SPACE
				4'd5: // R
					case (fy)
						3'd0: row_bits = 5'b11110;
						3'd1: row_bits = 5'b10001;
						3'd2: row_bits = 5'b10001;
						3'd3: row_bits = 5'b11110;
						3'd4: row_bits = 5'b10100;
						3'd5: row_bits = 5'b10010;
						3'd6: row_bits = 5'b10001;
						default: row_bits = 0;
					endcase
				4'd6: // U
					case (fy)
						3'd0: row_bits = 5'b10001;
						3'd1: row_bits = 5'b10001;
						3'd2: row_bits = 5'b10001;
						3'd3: row_bits = 5'b10001;
						3'd4: row_bits = 5'b10001;
						3'd5: row_bits = 5'b10001;
						3'd6: row_bits = 5'b01110;
						default: row_bits = 0;
					endcase
				4'd7, 4'd8: // N
					case (fy)
						3'd0: row_bits = 5'b10001;
						3'd1: row_bits = 5'b11001;
						3'd2: row_bits = 5'b10101;
						3'd3: row_bits = 5'b10011;
						3'd4: row_bits = 5'b10001;
						3'd5: row_bits = 5'b10001;
						3'd6: row_bits = 5'b10001;
						default: row_bits = 0;
					endcase
				4'd9: // E
					case (fy)
						3'd0: row_bits = 5'b11111;
						3'd1: row_bits = 5'b10000;
						3'd2: row_bits = 5'b10000;
						3'd3: row_bits = 5'b11110;
						3'd4: row_bits = 5'b10000;
						3'd5: row_bits = 5'b10000;
						3'd6: row_bits = 5'b11111;
						default: row_bits = 0;
					endcase
				4'd10: // R
					case (fy)
						3'd0: row_bits = 5'b11110;
						3'd1: row_bits = 5'b10001;
						3'd2: row_bits = 5'b10001;
						3'd3: row_bits = 5'b11110;
						3'd4: row_bits = 5'b10100;
						3'd5: row_bits = 5'b10010;
						3'd6: row_bits = 5'b10001;
						default: row_bits = 0;
					endcase
				default: row_bits = 0;
			endcase
			is_font_pixel = row_bits[4 - fx];
		end
	end
endfunction

// Unique Vibrant Color for Each Title Letter
function [23:0] get_title_color;
	input [3:0] char_idx;
	begin
		case (char_idx)
			4'd0:  get_title_color = 24'hFF3D00; // D: Crimson Red
			4'd1:  get_title_color = 24'hFF9100; // I: Bright Orange
			4'd2:  get_title_color = 24'hFFEA00; // N: Golden Yellow
			4'd3:  get_title_color = 24'h00E676; // O: Mint Green
			4'd4:  get_title_color = 24'hFFFFFF; // Space
			4'd5:  get_title_color = 24'h00E5FF; // R: Electric Cyan
			4'd6:  get_title_color = 24'h2979FF; // U: Royal Blue
			4'd7:  get_title_color = 24'h651FFF; // N: Bright Purple
			4'd8:  get_title_color = 24'hF50057; // N: Magenta
			4'd9:  get_title_color = 24'hD500F9; // E: Neon Violet
			4'd10: get_title_color = 24'hFF1744; // R: Hot Pink
			default: get_title_color = 24'hFFFFFF;
		endcase
	end
endfunction

wire draw_title = in_title_box && is_font_pixel(title_char_idx, font_x, font_y);
wire [23:0] title_color = get_title_color(title_char_idx);

function [23:0] rgb323_to_bgr888;
	input [7:0] c;
	reg [7:0] r, g, b;
	begin
		r = {c[7:5], c[7:5], c[7:6]};
		g = {c[4:3], c[4:3], c[4:3], c[4:3]};
		b = {c[2:0], c[2:0], c[2:1]};
		rgb323_to_bgr888 = {b, g, r};
	end
endfunction

wire draw_left_arrow  = can_go_left  && is_left_arrow_pixel(pixel_x, pixel_y);
wire draw_right_arrow = can_go_right && is_right_arrow_pixel(pixel_x, pixel_y);

// Pipeline registers for alignment with 1-cycle registered ROM read
reg show_d, in_char_square_d, draw_left_arrow_d, draw_right_arrow_d, draw_title_d;
reg [23:0] title_color_d;
reg [SVO_BITS_PER_PIXEL-1:0] base_d;
reg [0:0] tuser_d;
reg tvalid_d;

assign in_axis_tready  = out_axis_tready;
assign out_axis_tvalid = tvalid_d;
assign out_axis_tuser  = tuser_d;

wire [23:0] active_dino_bgr = rgb323_to_bgr888(dino_rgb);

// Transparent pixel test (0x00 is transparent)
wire is_dino_pixel = in_char_square_d && (dino_rgb != 8'h00);

assign out_axis_tdata =
	(!show_d)            ? base_d :
	(draw_title_d)       ? title_color_d :
	(draw_left_arrow_d)  ? COLOR_ARROW :
	(draw_right_arrow_d) ? COLOR_ARROW :
	(is_dino_pixel)      ? active_dino_bgr :
	                       COLOR_WHITE;

always @(posedge clk) begin
	if (!resetn) begin
		show_d             <= 0;
		in_char_square_d   <= 0;
		draw_left_arrow_d  <= 0;
		draw_right_arrow_d <= 0;
		draw_title_d       <= 0;
		title_color_d      <= 0;
		base_d             <= 0;
		tuser_d            <= 0;
		tvalid_d           <= 0;
	end else if (out_axis_tready) begin
		tvalid_d <= in_axis_tvalid;
		if (fire) begin
			show_d             <= show;
			in_char_square_d   <= in_char_square;
			draw_left_arrow_d  <= draw_left_arrow;
			draw_right_arrow_d <= draw_right_arrow;
			draw_title_d       <= draw_title;
			title_color_d      <= title_color;
			base_d             <= in_axis_tdata;
			tuser_d            <= in_axis_tuser;
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

endmodule
