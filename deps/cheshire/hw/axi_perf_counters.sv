// Copyright (c) 2019 ETH Zurich, University of Bologna
// All rights reserved.
//
// This code is under development and not yet released to the public.
// Until it is released, the code is under the copyright of ETH Zurich and
// the University of Bologna, and may contain confidential and/or unpublished
// work. Any reuse/redistribution is strictly forbidden without written
// permission from ETH Zurich.
//
// Thomas Benz <tbenz@ethz.ch>

// Sample implementation of performance counters.

package axi_perf_pkg;
 typedef struct packed {
      logic [63:0] aw_stall_cnt, ar_stall_cnt, r_stall_cnt, w_stall_cnt, buf_w_stall_cnt, buf_r_stall_cnt;
      logic [63:0] aw_valid_cnt, aw_ready_cnt, aw_done_cnt, aw_bw;
      logic [63:0] ar_valid_cnt, ar_ready_cnt, ar_done_cnt, ar_bw;
      logic [63:0]  r_valid_cnt,  r_ready_cnt,  r_done_cnt,  r_bw;
      logic [63:0]  w_valid_cnt,  w_ready_cnt,  w_done_cnt,  w_bw;
      logic [63:0]  b_valid_cnt,  b_ready_cnt,  b_done_cnt;
      logic [63:0] next_id,       completed_id;
      logic [63:0] busy_cnt;
  } perf_t;

endpackage


module axi_perf_counters #(
    parameter int unsigned TRANSFER_ID_WIDTH  = -1, 
    parameter int unsigned DATA_WIDTH         = -1,
    parameter type          axi_req_t          = logic,
    parameter type          axi_rsp_t          = logic,
    parameter type          reg_req_t       = logic,
    parameter type          reg_rsp_t       = logic
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    //REGBUS interface
    input  reg_req_t                     reg_req_i,
    output reg_rsp_t                     reg_rsp_o,
    // AXI4 bus
    input  axi_req_t                     axi_req_i,
    input  axi_rsp_t                     axi_rsp_i,
    // ID input
    input  logic [TRANSFER_ID_WIDTH-1:0] next_id_i,
    input  logic [TRANSFER_ID_WIDTH-1:0] completed_id_i,
    // DMA busy
    input  logic                         busy_i,
    // performance bus
    output axi_perf_pkg::perf_t       perf_o
);

    typedef logic [63:0] reg_data_t;

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // internal state
    axi_perf_pkg::perf_t perf_d, perf_q;

    // need popcount common cell to get the number of bytes active in the strobe signal
    logic [$clog2(STRB_WIDTH)+1-1:0] num_bytes_written;
    popcount #(
        .INPUT_WIDTH ( STRB_WIDTH  )
    ) i_popcount (
        .data_i      ( axi_req_i.w.strb   ),
        .popcount_o  ( num_bytes_written      )
    );

    // see if counters should be increased
    always_comb begin : proc_next_perf_state

        // defualt: keep old value
        perf_d = perf_q;

        // aw
        if ((axi_req_i.aw_valid)) begin
               perf_d.aw_valid_cnt = perf_q.aw_valid_cnt + 'h1;
          end

        if ((axi_rsp_i.aw_ready)) begin
               perf_d.aw_ready_cnt = perf_q.aw_ready_cnt + 'h1;
          end

        if ((axi_rsp_i.aw_ready & axi_req_i.aw_valid)) begin
               perf_d.aw_done_cnt = perf_q.aw_done_cnt + 'h1;
          end

        if ((axi_rsp_i.aw_ready & axi_req_i.aw_valid)) begin
            perf_d.aw_bw = perf_q.aw_bw +
                               ((axi_req_i.aw.len + 1) << axi_req_i.aw.size);
          end

        if ((!axi_rsp_i.aw_ready & axi_req_i.aw_valid)) begin
               perf_d.aw_stall_cnt = perf_q.aw_stall_cnt + 'h1;
          end

        // ar
        if (( axi_req_i.ar_valid)) begin
               perf_d.ar_valid_cnt = perf_q.ar_valid_cnt + 'h1;
          end

        if (( axi_rsp_i.ar_ready)) begin
               perf_d.ar_ready_cnt = perf_q.ar_ready_cnt + 'h1;
          end

        if (( axi_rsp_i.ar_ready & axi_req_i.ar_valid)) begin
               perf_d.ar_done_cnt = perf_q.ar_done_cnt + 'h1;
          end

        if (( axi_rsp_i.ar_ready & axi_req_i.ar_valid)) begin
            perf_d.ar_bw = perf_q.ar_bw +
                               ((axi_req_i.ar.len + 1) << axi_req_i.ar.size);
          end

        if ((!axi_rsp_i.ar_ready & axi_req_i.ar_valid)) begin
               perf_d.ar_stall_cnt = perf_q.ar_stall_cnt + 'h1;
          end

        // r 
        if ((axi_rsp_i.r_valid)) begin
               perf_d.r_valid_cnt  = perf_q.r_valid_cnt  + 'h1;
          end

        if ((axi_req_i.r_ready)) begin
               perf_d.r_ready_cnt  = perf_q.r_ready_cnt  + 'h1;
          end

        if ((axi_req_i.r_ready &  axi_rsp_i.r_valid)) begin
               perf_d.r_done_cnt   = perf_q.r_done_cnt   + 'h1;
          end

        if ((axi_req_i.r_ready &  axi_rsp_i.r_valid)) begin
               perf_d.r_bw = perf_q.r_bw + DATA_WIDTH / 8;
          end

        if ((axi_req_i.r_ready & !axi_rsp_i.r_valid)) begin
               perf_d.r_stall_cnt = perf_q.r_stall_cnt + 'h1;
          end

        // w
        if ((axi_req_i.w_valid)) begin
               perf_d.w_valid_cnt = perf_q.w_valid_cnt + 'h1;
          end

        if ((axi_rsp_i.w_ready)) begin
               perf_d.w_ready_cnt = perf_q.w_ready_cnt + 'h1;
          end

        if ((axi_rsp_i.w_ready & axi_req_i.w_valid)) begin
               perf_d.w_done_cnt = perf_q.w_done_cnt + 'h1;
          end

        if ((axi_rsp_i.w_ready & axi_req_i.w_valid)) begin
               perf_d.w_bw = perf_q.w_bw + num_bytes_written;
          end

        if ((!axi_rsp_i.w_ready & axi_req_i.w_valid)) begin
               perf_d.w_stall_cnt = perf_q.w_stall_cnt  + 'h1;
          end

        // b 
        if ((axi_rsp_i.b_valid)) begin
               perf_d.b_valid_cnt = perf_q.b_valid_cnt + 'h1;
          end

        if ((axi_req_i.b_ready)) begin
               perf_d.b_ready_cnt = perf_q.b_ready_cnt + 'h1;
          end

        if ((axi_req_i.b_ready & axi_rsp_i.b_valid)) begin
               perf_d.b_done_cnt = perf_q.b_done_cnt + 'h1;
          end

        // buffer
        if (( axi_rsp_i.w_ready & !axi_req_i.w_valid)) begin
               perf_d.buf_w_stall_cnt = perf_q.buf_w_stall_cnt + 'h1;
          end

        if ((!axi_req_i.r_ready &  axi_rsp_i.r_valid)) begin
               perf_d.buf_r_stall_cnt = perf_q.buf_r_stall_cnt + 'h1;
          end

        // ids
        perf_d.next_id      = 32'h0 + next_id_i;
        perf_d.completed_id = 32'h0 + completed_id_i;

        // busy
        if ((busy_i)) begin
               perf_d.busy_cnt = perf_q.busy_cnt + 'h1;
          end
    
    end

    logic[6] sel_reg;

    assign sel_reg          =  reg_req_i.valid ? reg_req_i.addr >> 2 : 6'b0;

    assign reg_rsp_o.ready  = 1'b1;

    // Read from register
    always_comb begin : proc_comb_read
        reg_data_t [28] rfield;
        reg_rsp_o.rdata = '0;
        rfield = {
            reg_data_t'(perf_q.aw_valid_cnt),
            reg_data_t'(perf_q.aw_ready_cnt),
            reg_data_t'(perf_q.aw_done_cnt),
            reg_data_t'(perf_q.aw_bw),
            reg_data_t'(perf_q.aw_stall_cnt),
            reg_data_t'(perf_q.ar_valid_cnt),
            reg_data_t'(perf_q.ar_ready_cnt),
            reg_data_t'(perf_q.ar_done_cnt),
            reg_data_t'(perf_q.ar_bw),
            reg_data_t'(perf_q.ar_stall_cnt),
            reg_data_t'(perf_q.r_valid_cnt),
            reg_data_t'(perf_q.r_ready_cnt),
            reg_data_t'(perf_q.r_done_cnt),
            reg_data_t'(perf_q.r_bw),
            reg_data_t'(perf_q.r_stall_cnt),
            reg_data_t'(perf_q.w_valid_cnt),
            reg_data_t'(perf_q.w_ready_cnt),
            reg_data_t'(perf_q.w_done_cnt),
            reg_data_t'(perf_q.w_bw),
            reg_data_t'(perf_q.w_stall_cnt),
            reg_data_t'(perf_q.b_valid_cnt),
            reg_data_t'(perf_q.b_ready_cnt),
            reg_data_t'(perf_q.b_done_cnt),
            reg_data_t'(perf_q.buf_w_stall_cnt),
            reg_data_t'(perf_q.buf_r_stall_cnt),
            reg_data_t'(perf_q.next_id),
            reg_data_t'(perf_q.completed_id),
            reg_data_t'(perf_q.busy_cnt)
        };
        reg_rsp_o.rdata = rfield[sel_reg];
     
    end


    always_ff @(posedge clk_i or negedge rst_ni) begin : proc_counter
        if (!rst_ni) begin
            perf_q <= '0;
        end else begin
            perf_q <= perf_d;
        end
    end

    assign perf_o = perf_q;

endmodule