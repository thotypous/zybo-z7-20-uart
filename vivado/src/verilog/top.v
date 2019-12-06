// based on https://github.com/ucb-bar/fpga-zynq/blob/master/common/rocketchip_wrapper.v

`timescale 1ns / 1ps

`define ZYNQ_CLK_PERIOD  8.0
`define RC_CLK_MULT      8.0
`define RC_CLK_DIVIDE   20.0


module top
   (DDR_addr,
    DDR_ba,
    DDR_cas_n,
    DDR_ck_n,
    DDR_ck_p,
    DDR_cke,
    DDR_cs_n,
    DDR_dm,
    DDR_dq,
    DDR_dqs_n,
    DDR_dqs_p,
    DDR_odt,
    DDR_ras_n,
    DDR_reset_n,
    DDR_we_n,
    FIXED_IO_ddr_vrn,
    FIXED_IO_ddr_vrp,
    FIXED_IO_mio,
    FIXED_IO_ps_clk,
    FIXED_IO_ps_porb,
    FIXED_IO_ps_srstb,
    jd_rx,
    jd_tx,
    je_rx,
    je_tx,
    clk);

  inout [14:0]DDR_addr;
  inout [2:0]DDR_ba;
  inout DDR_cas_n;
  inout DDR_ck_n;
  inout DDR_ck_p;
  inout DDR_cke;
  inout DDR_cs_n;
  inout [3:0]DDR_dm;
  inout [31:0]DDR_dq;
  inout [3:0]DDR_dqs_n;
  inout [3:0]DDR_dqs_p;
  inout DDR_odt;
  inout DDR_ras_n;
  inout DDR_reset_n;
  inout DDR_we_n;

  inout FIXED_IO_ddr_vrn;
  inout FIXED_IO_ddr_vrp;
  inout [53:0]FIXED_IO_mio;
  inout FIXED_IO_ps_clk;
  inout FIXED_IO_ps_porb;
  inout FIXED_IO_ps_srstb;

  input  [3:0] jd_rx;
  output [3:0] jd_tx;
  input  [3:0] je_rx;
  output [3:0] je_tx;

  input clk;

  wire FCLK_RESET0_N;

  wire [31:0]M_AXI_araddr;
  wire [1:0]M_AXI_arburst;
  wire [7:0]M_AXI_arlen;
  wire M_AXI_arready;
  wire [2:0]M_AXI_arsize;
  wire M_AXI_arvalid;
  wire [31:0]M_AXI_awaddr;
  wire [1:0]M_AXI_awburst;
  wire [7:0]M_AXI_awlen;
  wire [3:0]M_AXI_wstrb;
  wire M_AXI_awready;
  wire [2:0]M_AXI_awsize;
  wire M_AXI_awvalid;
  wire M_AXI_bready;
  wire M_AXI_bvalid;
  wire [31:0]M_AXI_rdata;
  wire M_AXI_rlast;
  wire M_AXI_rready;
  wire M_AXI_rvalid;
  wire [31:0]M_AXI_wdata;
  wire M_AXI_wlast;
  wire M_AXI_wready;
  wire M_AXI_wvalid;
  wire [11:0] M_AXI_arid, M_AXI_awid; // outputs from ARM core
  wire [11:0] M_AXI_bid, M_AXI_rid;   // inputs to ARM core

  wire reset, reset_cpu;
  wire host_clk;
  wire gclk_i, gclk_fbout, host_clk_i, mmcm_locked;
  wire irq;


  system system_i
       (.DDR_addr(DDR_addr),
        .DDR_ba(DDR_ba),
        .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p),
        .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n),
        .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n),
        .DDR_dqs_p(DDR_dqs_p),
        .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n),
        .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n),
        .FCLK_RESET0_N(FCLK_RESET0_N),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio),
        .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        // master AXI interface (zynq = master, fpga = slave)
        .M_AXI_araddr(M_AXI_araddr),
        .M_AXI_arburst(M_AXI_arburst), // burst type
        .M_AXI_arcache(),
        .M_AXI_arid(M_AXI_arid),
        .M_AXI_arlen(M_AXI_arlen), // burst length (#transfers)
        .M_AXI_arlock(),
        .M_AXI_arprot(),
        .M_AXI_arqos(),
        .M_AXI_arready(M_AXI_arready),
        .M_AXI_arregion(),
        .M_AXI_arsize(M_AXI_arsize), // burst size (bits/transfer)
        .M_AXI_arvalid(M_AXI_arvalid),
        //
        .M_AXI_awaddr(M_AXI_awaddr),
        .M_AXI_awburst(M_AXI_awburst),
        .M_AXI_awcache(),
        .M_AXI_awid(M_AXI_awid),
        .M_AXI_awlen(M_AXI_awlen),
        .M_AXI_awlock(),
        .M_AXI_awprot(),
        .M_AXI_awqos(),
        .M_AXI_awready(M_AXI_awready),
        .M_AXI_awregion(),
        .M_AXI_awsize(M_AXI_awsize),
        .M_AXI_awvalid(M_AXI_awvalid),
        //
        .M_AXI_bid(M_AXI_bid),
        .M_AXI_bready(M_AXI_bready),
        .M_AXI_bresp(2'b00),
        .M_AXI_bvalid(M_AXI_bvalid),
        //
        .M_AXI_rdata(M_AXI_rdata),
        .M_AXI_rid(M_AXI_rid),
        .M_AXI_rlast(M_AXI_rlast),
        .M_AXI_rready(M_AXI_rready),
        .M_AXI_rresp(),
        .M_AXI_rvalid(M_AXI_rvalid),
        //
        .M_AXI_wdata(M_AXI_wdata),
        .M_AXI_wlast(M_AXI_wlast),
        .M_AXI_wready(M_AXI_wready),
        .M_AXI_wstrb(M_AXI_wstrb),
        .M_AXI_wvalid(M_AXI_wvalid),

        .ext_clk_in(host_clk),
        .irq_in(irq)
        );

  assign reset = !FCLK_RESET0_N || !mmcm_locked;

  mkTop mytop(
   .CLK(host_clk),
   .RST_N(!reset),

   .axi_slave_awready (M_AXI_awready),
   .axi_slave_awvalid (M_AXI_awvalid),
   .axi_slave_awaddr (M_AXI_awaddr),
   .axi_slave_awlen (M_AXI_awlen),
   .axi_slave_awsize (M_AXI_awsize),
   .axi_slave_awburst (M_AXI_awburst),
   .axi_slave_awid (M_AXI_awid),
   .axi_slave_awlock (1'b0),
   .axi_slave_awcache (4'b0),
   .axi_slave_awprot (3'b0),
   .axi_slave_awqos (4'b0),

   .axi_slave_arready (M_AXI_arready),
   .axi_slave_arvalid (M_AXI_arvalid),
   .axi_slave_araddr (M_AXI_araddr),
   .axi_slave_arlen (M_AXI_arlen),
   .axi_slave_arsize (M_AXI_arsize),
   .axi_slave_arburst (M_AXI_arburst),
   .axi_slave_arid (M_AXI_arid),
   .axi_slave_arlock (1'b0),
   .axi_slave_arcache (4'b0),
   .axi_slave_arprot (3'b0),
   .axi_slave_arqos (4'b0),

   .axi_slave_wvalid (M_AXI_wvalid),
   .axi_slave_wready (M_AXI_wready),
   .axi_slave_wdata (M_AXI_wdata),
   .axi_slave_wstrb (M_AXI_wstrb),
   .axi_slave_wlast (M_AXI_wlast),

   .axi_slave_rvalid (M_AXI_rvalid),
   .axi_slave_rready (M_AXI_rready),
   .axi_slave_rid (M_AXI_rid),
   .axi_slave_rresp (M_AXI_rresp),
   .axi_slave_rdata (M_AXI_rdata),
   .axi_slave_rlast (M_AXI_rlast),

   .axi_slave_bvalid (M_AXI_bvalid),
   .axi_slave_bready (M_AXI_bready),
   .axi_slave_bid (M_AXI_bid),
   .axi_slave_bresp (M_AXI_bresp),

   .axi_irq(irq),

   .serial_0_tx(jd_tx[0]),
   .serial_1_tx(jd_tx[1]),
   .serial_2_tx(jd_tx[2]),
   .serial_3_tx(jd_tx[3]),
   .serial_4_tx(je_tx[0]),
   .serial_5_tx(je_tx[1]),
   .serial_6_tx(je_tx[2]),
   .serial_7_tx(je_tx[3]),

   .serial_0_rx(jd_rx[0]),
   .serial_1_rx(jd_rx[1]),
   .serial_2_rx(jd_rx[2]),
   .serial_3_rx(jd_rx[3]),
   .serial_4_rx(je_rx[0]),
   .serial_5_rx(je_rx[1]),
   .serial_6_rx(je_rx[2]),
   .serial_7_rx(je_rx[3])
  );
  IBUFG ibufg_gclk (.I(clk), .O(gclk_i));
  BUFG  bufg_host_clk (.I(host_clk_i), .O(host_clk));

  MMCME2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKFBOUT_MULT_F(`RC_CLK_MULT),
    .CLKFBOUT_PHASE(0.0),
    .CLKIN1_PERIOD(`ZYNQ_CLK_PERIOD),
    .CLKOUT1_DIVIDE(1),
    .CLKOUT2_DIVIDE(1),
    .CLKOUT3_DIVIDE(1),
    .CLKOUT4_DIVIDE(1),
    .CLKOUT5_DIVIDE(1),
    .CLKOUT6_DIVIDE(1),
    .CLKOUT0_DIVIDE_F(`RC_CLK_DIVIDE),
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT1_DUTY_CYCLE(0.5),
    .CLKOUT2_DUTY_CYCLE(0.5),
    .CLKOUT3_DUTY_CYCLE(0.5),
    .CLKOUT4_DUTY_CYCLE(0.5),
    .CLKOUT5_DUTY_CYCLE(0.5),
    .CLKOUT6_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE(0.0),
    .CLKOUT1_PHASE(0.0),
    .CLKOUT2_PHASE(0.0),
    .CLKOUT3_PHASE(0.0),
    .CLKOUT4_PHASE(0.0),
    .CLKOUT5_PHASE(0.0),
    .CLKOUT6_PHASE(0.0),
    .CLKOUT4_CASCADE("FALSE"),
    .DIVCLK_DIVIDE(1),
    .REF_JITTER1(0.0),
    .STARTUP_WAIT("FALSE")
  ) MMCME2_BASE_inst (
    .CLKOUT0(host_clk_i),
    .CLKOUT0B(),
    .CLKOUT1(),
    .CLKOUT1B(),
    .CLKOUT2(),
    .CLKOUT2B(),
    .CLKOUT3(),
    .CLKOUT3B(),
    .CLKOUT4(),
    .CLKOUT5(),
    .CLKOUT6(),
    .CLKFBOUT(gclk_fbout),
    .CLKFBOUTB(),
    .LOCKED(mmcm_locked),
    .CLKIN1(gclk_i),
    .PWRDWN(1'b0),
    .RST(1'b0),
    .CLKFBIN(gclk_fbout));

endmodule
