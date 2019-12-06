// Copyright (c) 2014 Quanta Research Cambridge, Inc.
// Copyright (c) 2019 Paulo Matias

// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import BUtils::*;
import GetPut::*;
import Connectable::*;

// Parameters ...
typedef 115_200      BaudRate;
typedef 50_000_000   ClockFreq;
typedef TDiv#(ClockFreq, BaudRate) BaudCycles;

typedef Bit#(8) Byte;

// Interfaces
interface UartRx;
	interface Get#(Byte) rx;
	interface UartRxWires wires;
	(* always_ready *)
	method Bool frm_err;
endinterface

interface UartTx;
	interface Put#(Byte) tx;
	interface UartTxWires wires;
endinterface


interface UartRxWires;
	(* always_ready, always_enabled, prefix="" *)
	method Action put((*port="rx"*)Bit#(1) b);
endinterface

interface UartTxWires;
	(* always_ready, result="tx" *)
	method Bit#(1) get;
endinterface

interface UartRxCtl;
	(* always_ready, always_enabled *)
	method Action baud_x16(Bool en);

	(* always_ready, always_enabled *)
	method Action rxd_clk(Bit#(1) rx);

	(* ready="rx_data_rdy" *)
	method Byte rx_data;

	(* always_ready *)
	method Bool frm_err;
endinterface

interface UartBaudGen#(numeric type baud_rate, numeric type clock_rate);
	(* always_ready *)
	method Bool baud_x16_en;
endinterface

// Modules ...
module mkUartRx(UartRx);

	UartRxCtl uctl <- mkUartRxCtl;
	UartBaudGen#(BaudRate, ClockFreq) baud <- mkUartBaudGenSynth;
	Reg#(Bit#(3)) asyncSync <- mkReg(0);

	rule connect_baud;
		uctl.baud_x16(baud.baud_x16_en);
	endrule

	rule connect_rxd_clk;
		uctl.rxd_clk(asyncSync[2]);
	endrule

	interface Get rx;
		method ActionValue#(Byte) get;
			return uctl.rx_data;
		endmethod
	endinterface
	interface UartRxWires wires;
		method Action put(Bit#(1) b);
			asyncSync <= {asyncSync[1:0], b};
		endmethod
	endinterface
	method frm_err = uctl.frm_err;

endmodule

// typedef is forbidden inside module
typedef enum {IDLE, START, DATA, STOP}  State deriving(Bits, Eq);

module mkUartRxCtl(UartRxCtl);

	Reg#(State)              state <- mkReg(IDLE);
	Reg#(Bit#(4))  over_sample_cnt <- mkReg(0);
	Reg#(Bit#(3))          bit_cnt <- mkReg(0);

	Wire#(Bool)    over_sample_cnt_done <- mkWire;
	Wire#(Bool)            bit_cnt_done <- mkWire;
	Wire#(Bit#(1))                  rxd <- mkBypassWire;
	Wire#(Bool)                  x16_en <- mkBypassWire;

	// output registers
	Reg#(Byte)              rx_data_reg <- mkReg(0);
	Reg#(Bool)          rx_data_rdy_reg <- mkReg(False);
	Reg#(Bool)              frm_err_reg <- mkReg(False);

	rule main_state_machine (x16_en == True);
		case(state)
			IDLE: begin
				if (rxd == 1'b0)
					state <= START;
				end
			START: begin
				// After 1/2 bit period, re-confirm the start state
				if (over_sample_cnt_done) begin
					if (rxd == 1'b0)
						state <= DATA; // was a legitimate start bit (not a glitch)
					else
						state <= IDLE; // was a glitch - reject
					end
				end
			DATA: begin
				if (over_sample_cnt_done && bit_cnt_done)
					state <= STOP;
				end
			STOP: begin
				if (over_sample_cnt_done)
					state <= IDLE;
				end
		endcase
	endrule

	rule update_over_sample_cnt_done;
		over_sample_cnt_done <= (over_sample_cnt == 0);
		bit_cnt_done <= (bit_cnt == 3'd7);
	endrule

	rule oversample_counter (x16_en == True);
		if (over_sample_cnt_done == False)
			over_sample_cnt <= over_sample_cnt - 1;
		else if ((state == IDLE) && (rxd == 0) )
			over_sample_cnt <= 4'd7;
		else if ( ((state == START) && (rxd == 1'b0)) || (state == DATA) )
			over_sample_cnt <= 4'd15;
	endrule

	rule track_rx_bit(x16_en == True);
		if (over_sample_cnt_done == True)
			if (state == START)
				bit_cnt <= 3'd0;
			else if (state == DATA)
				bit_cnt <= bit_cnt + 1;
	endrule

	rule capture_data;
		if (x16_en && over_sample_cnt_done)
			if (state == DATA) begin
				rx_data_reg[bit_cnt] <= rxd;
				rx_data_rdy_reg <= (bit_cnt == 3'd7); // counting from 0
			end else
				rx_data_rdy_reg <= False;
	endrule

	rule frame_err_generation(x16_en == True);
		frm_err_reg <=  ((state == STOP) && over_sample_cnt_done && (rxd == 1'b0));
	endrule


	// Interface
	method Action rxd_clk(Bit#(1) rx);
		rxd <= rx;
	endmethod
	method Action baud_x16(Bool en);
		x16_en <= en;
	endmethod
	method rx_data if(rx_data_rdy_reg == True);
		return rx_data_reg;
	endmethod
	method frm_err = frm_err_reg;

endmodule

// polymorphic hence can't synthesize
module mkUartBaudGen(UartBaudGen#(baud_rate, clock_rate))
	provisos(
		Mul#(baud_rate, 16, oversample_rate),          // oversample_rate = baud_rate * 16
		Div#(clock_rate, oversample_rate, divider),    // divider = Ceil(clock_rate/oversample_rate)
		Add#(1, oversample_value, divider),            // 1+oversample_value = divider => oversample_value = divider-1
		Log#(divider, cnt_wid)                         // cnt_wid = Ceil(log2(divider))
	);

	Reg#(Bit#(cnt_wid))  internal_count  <- mkReg(fromInteger(valueOf(oversample_value)));
	Reg#(Bool)           baud_x16_en_reg <- mkReg(False);


	rule assert_baud_x16_en;
		let internal_count_m_1 = internal_count - 1;
		baud_x16_en_reg <= (internal_count_m_1 == 0);

		if (internal_count == 0)
			internal_count <= fromInteger(valueOf(oversample_value));
		else
			internal_count <= internal_count_m_1;
	endrule

	method baud_x16_en = baud_x16_en_reg;
endmodule

module mkUartBaudGenSynth(UartBaudGen#(BaudRate, ClockFreq));
	UartBaudGen#(BaudRate, ClockFreq) _u  <- mkUartBaudGen;
	return _u;
endmodule


typedef Bit#(TLog#(BaudCycles)) Phase;
Integer baudCycles = valueOf(BaudCycles);
Phase maxPhase = fromInteger(baudCycles - 1);

module mkUartTx(UartTx);
	Reg#(Bit#(1)) outb <- mkReg(1);
	Reg#(Bit#(10)) shiftReg <- mkReg(0); // {stop_bit, data, start_bit}
	Reg#(Phase) phase <- mkReg(0);
	let idle = shiftReg == 0 && phase == 0;

	(* no_implicit_conditions, fire_when_enabled *)
	rule produceOut (!idle);
		phase <= phase == maxPhase ? 0 : phase + 1;
		if (phase == 0) begin
			outb <= shiftReg[0];
			shiftReg <= shiftReg >> 1;
		end
	endrule

	(* no_implicit_conditions, fire_when_enabled *)
	rule clearOut (idle);
		outb <= 1;
	endrule

	interface Put tx;
		method Action put(Byte b) if (idle);
			shiftReg <= {1'b1, b, 1'b0};
			phase <= 0;
		endmethod
	endinterface

	interface UartTxWires wires;
		method get = outb;
	endinterface
endmodule


instance Connectable#(UartTxWires, UartRxWires);
	module mkConnection#(UartTxWires tx, UartRxWires rx)(Empty);
		mkConnection(tx.get, rx.put);
	endmodule
endinstance

instance Connectable#(UartRxWires, UartTxWires);
	module mkConnection#(UartRxWires rx, UartTxWires tx)(Empty);
		mkConnection(rx.put, tx.get);
	endmodule
endinstance
