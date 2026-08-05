`timescale 1ns / 1ps

module bin2bcd #(
	parameter BIN_BITS = 12
) (
	input [BIN_BITS-1:0] bin,
	output reg [11:0] bcd
);

integer i;
reg [BIN_BITS+12-1:0] shift;

always @(*) begin
	shift = 0;
	shift[BIN_BITS-1:0] = bin;

	for (i = 0; i < BIN_BITS; i = i + 1) begin
		if (shift[BIN_BITS + 3 : BIN_BITS] >= 4'd5)
			shift[BIN_BITS + 3 : BIN_BITS] =
				shift[BIN_BITS + 3 : BIN_BITS] + 4'd3;

		if (shift[BIN_BITS + 7 : BIN_BITS + 4] >= 4'd5)
			shift[BIN_BITS + 7 : BIN_BITS + 4] =
				shift[BIN_BITS + 7 : BIN_BITS + 4] + 4'd3;

		if (shift[BIN_BITS + 11 : BIN_BITS + 8] >= 4'd5)
			shift[BIN_BITS + 11 : BIN_BITS + 8] =
				shift[BIN_BITS + 11 : BIN_BITS + 8] + 4'd3;

		shift = shift << 1;
	end

	bcd = shift[BIN_BITS + 11 : BIN_BITS];
end

endmodule
