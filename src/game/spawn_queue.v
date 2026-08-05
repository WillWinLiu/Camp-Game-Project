`timescale 1ns / 1ps

module spawn_queue #(
	parameter FIFO_DEPTH = 4,
	parameter FIFO_ADDR_W = 2,
	parameter [31:0] POS_SEED = 32'hACE1_1234,
	parameter [31:0] TYPE_SEED = 32'h1D2C_3B4A
) (
	input wire clk,
	input wire resetn,
	input wire enable,

	input wire pop,
	output wire [10:0] spawn_data,
	output wire empty,

	output wire full,
	output wire [FIFO_ADDR_W:0] level
);

wire [31:0] pos_rnd;
wire [31:0] type_rnd;
wire [3:0] cand_lane = pos_rnd[3:0];
wire [3:0] cand_xoff = pos_rnd[7:4];
wire [6:0] cand_pct  = type_rnd[6:0];
reg [2:0] clump_cnt;

wire is_cactus_raw = (cand_pct < 50);
wire force_non_cactus = (is_cactus_raw && clump_cnt >= 4);
wire [2:0] cand_type = force_non_cactus ? 3'd1 : (is_cactus_raw ? 3'd0 : 3'd1);

wire cand_valid = cand_pct < 100;
wire cand_next = enable && !full;
wire fifo_wr_en = cand_next && cand_valid;
wire [10:0] fifo_wr_data = {cand_lane, cand_xoff, cand_type};

always @(posedge clk) begin
	if (!resetn) begin
		clump_cnt <= 0;
	end else if (fifo_wr_en) begin
		if (cand_type == 3'd0) begin
			clump_cnt <= clump_cnt + 1;
		end else begin
			clump_cnt <= 0;
		end
	end
end

lfsr32 #(
	.SEED(POS_SEED)
) u_pos_lfsr (
	.clk(clk),
	.resetn(resetn),
	.en(cand_next),
	.rnd(pos_rnd)
);

lfsr32 #(
	.SEED(TYPE_SEED)
) u_type_lfsr (
	.clk(clk),
	.resetn(resetn),
	.en(cand_next),
	.rnd(type_rnd)
);

fifo #(
	.WIDTH(11),
	.DEPTH(FIFO_DEPTH)
) u_spawn_fifo (
	.clk(clk),
	.resetn(resetn),
	.wr_en(fifo_wr_en),
	.wr_data(fifo_wr_data),
	.full(full),
	.rd_en(pop),
	.rd_data(spawn_data),
	.empty(empty),
	.level(level)
);
endmodule
