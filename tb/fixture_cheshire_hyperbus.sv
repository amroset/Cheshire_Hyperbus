// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Jannis Schönleber <janniss@iis.ee.ethz.ch>

  timeunit 1ps;
  timeprecision 1ps;


/// Testbench bixture of Iguana: derived from the Cheshire fixture
module fixture_cheshire_hyperbus #(
  /// The selected simulation configuration from the `tb_cheshire_pkg`.
  parameter int unsigned SelectedCfg = 32'd0,
  parameter bit          UseDramSys  = 1'b0
);

  `include "cheshire/typedef.svh"

  import cheshire_pkg::*;
  import cheshire_hyperbus_pkg::*;
  import tb_cheshire_hyperbus_pkg::*;

  localparam cheshire_cfg_t DutCfg = TbCheshireConfigs[SelectedCfg];

  `CHESHIRE_TYPEDEF_ALL(, DutCfg)

  ///////////
  //  DUT  //
  ///////////

  wire       clk;
  wire       rst_n;
  wire       test_mode;
  wire [1:0] boot_mode;
  wire       rtc;

  wire jtag_tck;
  wire jtag_trst_n;
  wire jtag_tms;
  wire jtag_tdi;
  wire jtag_tdo;

  wire uart_tx;
  wire uart_rx;

  wire i2c_sda;
  wire i2c_scl;

  wire                 spih_sck;
  wire [SpihNumCs-1:0] spih_csb;
  wire [ 3:0]          spih_sd;

  wire [GpioNumWired-1:0] gpio;

  wire [SlinkNumChan-1:0]                    slink_rcv_clk_i;
  wire [SlinkNumChan-1:0]                    slink_rcv_clk_o;
  wire [SlinkNumChan-1:0][SlinkNumLanes-1:0] slink_i;
  wire [SlinkNumChan-1:0][SlinkNumLanes-1:0] slink_o;

  wire [HypNumPhys-1:0][HypNumChips-1:0]  hyper_cs_no;
  wire [HypNumPhys-1:0]                   hyper_ck_o;
  wire [HypNumPhys-1:0]                   hyper_ck_no;
  wire [HypNumPhys-1:0]                   hyper_reset_no;

  wire [HypNumPhys-1:0]                   hyper_rwds;
  wire [HypNumPhys-1:0][7:0]              hyper_dq;

  //SIGNALS TO BE TRISTATE ADAPTED
  // I2C interface
  logic i2c_sda_o;
  logic i2c_sda_i;
  logic i2c_sda_en;

  logic i2c_scl_o;
  logic i2c_scl_i;
  logic i2c_scl_en;

  // I2C
  bufif1 (i2c_sda_i, i2c_sda, ~i2c_sda_en);
  bufif1 (i2c_sda, i2c_sda_o,  i2c_sda_en);
  bufif1 (i2c_scl_i, i2c_scl, ~i2c_scl_en);
  bufif1 (i2c_scl, i2c_scl_o,  i2c_scl_en);
  pullup (i2c_sda);
  pullup (i2c_scl);

  // SPI host interface
  logic                 spih_sck_o;
  logic                 spih_sck_en;

  logic [ 3:0]          spih_sd_o;
  logic [ 3:0]          spih_sd_en;
  logic [ 3:0]          spih_sd_i;

  logic [SpihNumCs-1:0] spih_csb_o;
  logic [SpihNumCs-1:0] spih_csb_en;
  

  // SPI
  bufif1 (spih_sck, spih_sck_o, spih_sck_en);
  pullup (spih_sck);

  for (genvar i = 0; i < 4; ++i) begin : gen_spih_sd_io
    bufif1 (spih_sd_i[i], spih_sd[i], ~spih_sd_en[i]);
    bufif1 (spih_sd[i], spih_sd_o[i],  spih_sd_en[i]);
    pullup (spih_sd[i]);
  end

  for (genvar i = 0; i < SpihNumCs; ++i) begin : gen_spih_cs_io
    bufif1 (spih_csb[i], spih_csb_o[i], spih_csb_en[i]);
    pullup (spih_csb[i]);
  end

  //Hyperbus interface
  // Hyperbus

  logic [HypNumPhys-1:0]                  hyper_rwds_o;
  logic [HypNumPhys-1:0]                  hyper_rwds_i;
  logic [HypNumPhys-1:0]                  hyper_rwds_oe;

  logic [HypNumPhys-1:0][7:0]             hyper_dq_o;
  logic [HypNumPhys-1:0][7:0]             hyper_dq_i;
  logic [HypNumPhys-1:0]                  hyper_dq_oe;

  for (genvar i = 0; i < HypNumPhys; ++i) begin : gen_hyper_rwds_io
    bufif1 (hyper_rwds_i[i], hyper_rwds[i], ~hyper_rwds_oe[i]);
    bufif1 (hyper_rwds[i], hyper_rwds_o[i],  hyper_rwds_oe[i]);
    pullup (hyper_rwds[i]);
  end

  for (genvar i = 0; i < HypNumPhys; ++i) begin : gen_hyper_dq_io
    for(genvar j = 0; j < 8; ++j) begin 
      bufif1 (hyper_dq_i[i][j], hyper_dq[i][j], ~hyper_dq_oe[i]);
      bufif1 (hyper_dq[i][j], hyper_dq_o[i][j],  hyper_dq_oe[i]);
      pullup (hyper_dq[i][j]);
    end
  end



  cheshire_hyperbus_soc  i_dut (
    .clk_i            ( clk      ),
    .rst_ni           ( rst_n      ),
    .test_mode_i      ( test_mode ),
    .boot_mode_i      ( boot_mode ),
    .rtc_i            ( rtc       ),
    .jtag_tck_i       ( jtag_tck    ),
    .jtag_trst_ni     ( jtag_trst_n  ),
    .jtag_tms_i       ( jtag_tms    ),
    .jtag_tdi_i       ( jtag_tdi    ),
    .jtag_tdo_o       ( jtag_tdo    ),
    .jtag_tdo_oe_o    (),
    .uart_tx_o        ( uart_tx ),
    .uart_rx_i        ( uart_rx ),
    .i2c_sda_o        ( i2c_sda_o    ),
    .i2c_sda_i        ( i2c_sda_i    ),
    .i2c_sda_en_o     ( i2c_sda_en ),
    .i2c_scl_o        ( i2c_scl_o    ),
    .i2c_scl_i        ( i2c_scl_i    ),
    .i2c_scl_en_o     ( i2c_scl_en ),
    .spih_sck_o       ( spih_sck_o    ),
    .spih_sck_en_o    ( spih_sck_en ),
    .spih_csb_o       ( spih_csb_o    ),
    .spih_csb_en_o    ( spih_csb_en ),
    .spih_sd_o        ( spih_sd_o     ),
    .spih_sd_en_o     ( spih_sd_en  ),
    .spih_sd_i        ( spih_sd_i     ),
    .usb_clk_i        ( ),
    .gpio_i           (    ),
    .gpio_o           (    ),
    .gpio_en_o        (  ),
    .slink_rcv_clk_i  ( slink_rcv_clk_i ),
    .slink_rcv_clk_o  ( slink_rcv_clk_o ),
    .slink_i          ( slink_i     ),
    .slink_o          ( slink_o     ),
    .vga_hsync_o      ( ),
    .vga_vsync_o      (  ),
    .vga_red_o        (    ),
    .vga_green_o      (  ),
    .vga_blue_o       (   ),
    .hyper_cs_no      ( hyper_cs_no     ),
    .hyper_ck_o       ( hyper_ck_o      ),
    .hyper_ck_no      ( hyper_ck_no     ),
    .hyper_rwds_o     ( hyper_rwds_o    ),
    .hyper_rwds_i     ( hyper_rwds_i    ),
    .hyper_rwds_oe_o  ( hyper_rwds_oe ),
    .hyper_dq_i       ( hyper_dq_i      ),
    .hyper_dq_o       ( hyper_dq_o      ),
    .hyper_dq_oe_o    ( hyper_dq_oe   ),
    .hyper_reset_no   ( hyper_reset_no  )
  );

  ///////////////
  // HyperBus  //
  //////////////

  for (genvar i=0; i<HypNumChips; i++) begin : gen_hyp_chips

    s27ks0641 #(
      .TimingModel ( "S27KS0641DPBHI020" )
    ) i_hyper (
      .CK       ( hyper_ck_o  ),
      .CKNeg    ( hyper_ck_no ),
      .RESETNeg ( hyper_reset_no ),
      .RWDS     ( hyper_rwds[0] ),
      .CSNeg    ( hyper_cs_no[0][i] ),
      .DQ0      ( hyper_dq[0][0] ),
      .DQ1      ( hyper_dq[0][1] ),
      .DQ2      ( hyper_dq[0][2] ),
      .DQ3      ( hyper_dq[0][3] ),
      .DQ4      ( hyper_dq[0][4] ),
      .DQ5      ( hyper_dq[0][5] ),
      .DQ6      ( hyper_dq[0][6] ),
      .DQ7      ( hyper_dq[0][7] )
    ); //REPLACE 0 with i to assign more than one phy

    initial $sdf_annotate("../models/s27ks0641/s27ks0641.sdf", i_hyper);

  end

  ///////////
  //  VIP  //
  ///////////

  // External AXI LLC (DRAM) port stub
  axi_llc_req_t axi_llc_mst_req;
  axi_llc_rsp_t axi_llc_mst_rsp;

  axi_mst_req_t axi_slink_mst_req;
  axi_mst_rsp_t axi_slink_mst_rsp;

  assign axi_slink_mst_req = '0;

  vip_cheshire_soc #(
    .DutCfg             ( DutCfg ),
    .axi_ext_llc_req_t  ( axi_llc_req_t ),
    .axi_ext_llc_rsp_t  ( axi_llc_rsp_t ),
    .axi_ext_mst_req_t ( axi_mst_req_t ),
    .axi_ext_mst_rsp_t ( axi_mst_rsp_t ),
    .ClkPeriodSys       ( 10000 ),
    .ClkPeriodJtag      ( 40000 ),
    .RstCycles          ( 20 )
  ) vip (.*);

endmodule