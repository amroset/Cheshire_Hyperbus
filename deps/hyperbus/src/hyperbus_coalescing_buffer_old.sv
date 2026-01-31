`include "common_cells/registers.svh"

module hyperbus_coalescing_buffer #(
  /// Maximum number of in flight read transactions.
  parameter int unsigned MaxReadTxns  = 32'd0,
  /// Maximum number of in flight write transactions.
  parameter int unsigned MaxWriteTxns = 32'd0,
  /// AXI4+ATOP ID width.
  parameter int unsigned AxiIdWidth   = 32'd0,
  /// AXI4+ATOP request struct definition.
  parameter type         req_t        = logic,
  /// AXI4+ATOP response struct definition.
  parameter type         resp_t       = logic,
  /// AXI ADDR WIDTH
  parameter int unsigned AddrWidth    = 48,
  ///AXI DATA WIDTH
  parameter int unsigned DataWidth    = 64,
  ///TARGET BURST SIZE
  parameter int unsigned BurstSize  = 128,
  /// cycles before issuing 512B
  parameter int unsigned CoalWindow   = 100
  
) (
  /// Clock
  input  logic  clk_i,
  /// Asynchronous reset, active low
  input  logic  rst_ni,
  /// Slave port request
  input  req_t  slv_req_i,
  /// Slave port response
  output resp_t slv_resp_o,
  /// Master port request
  output req_t  mst_req_o,
  /// Master port response
  input  resp_t mst_resp_i
);

///////////////////////////READING BUFFER///////////////////////////////////

typedef enum logic [1:0] {IDLE, REQUEST, SERVE} state_t;
state_t state_d, state_q;

logic hit;

logic[AddrWidth-1:0] base_addr_d, base_addr_q, max_addr, addr_end, max_addr_d, max_addr_q;

//address to access sram

localparam int unsigned SramAddrWidth = $clog2(BurstSize);

logic [SramAddrWidth-1:0] addr_sram_d, addr_sram_q;


//request length to manage narrow transfers
logic [$clog2(BurstSize)-1:0] req_len_d, req_len_q;


//fill counter for writing on SRAM
logic [$clog2(BurstSize)-1:0] fill_cnt_d, fill_cnt_q;

//address id
logic [AxiIdWidth-1:0] rid_d, rid_q;

//SRAM control signals
logic req_sram;
logic req_sram_d, req_sram_q;
logic write_en_d, write_en_q;

logic ar_valid_d, ar_valid_q;
logic r_valid_d, r_valid_q;
logic ar_ready_d, ar_ready_q;
logic r_ready_d, r_ready_q;

logic last_d, last_q;

logic new_req_d, new_req_q;

logic pending_d, pending_q;

//intraword strobe for write
logic [7:0] byte_en;



//registers
`FF(state_q, state_d, IDLE, clk_i, rst_ni)
`FF(ar_valid_q, ar_valid_d, 1'b0, clk_i, rst_ni)
`FF(r_valid_q, r_valid_d, 1'b0, clk_i, rst_ni)
`FF(req_sram_q, req_sram_d, 1'b0, clk_i, rst_ni)
`FF(req_len_q, req_len_d, '0, clk_i, rst_ni)
`FF(ar_ready_q, ar_ready_d, '0, clk_i, rst_ni)
`FF(r_ready_q, r_ready_d, '0, clk_i, rst_ni)
`FF(write_en_q, write_en_d, '0, clk_i, rst_ni)
`FF(rid_q, rid_d, '0, clk_i, rst_ni)
`FF(fill_cnt_q, fill_cnt_d, '0, clk_i, rst_ni)
`FF(base_addr_q, base_addr_d, '0, clk_i, rst_ni)
`FF(addr_sram_q, addr_sram_d, '0, clk_i, rst_ni)
`FF(last_q, last_d, '0, clk_i, rst_ni)
`FF(new_req_q, new_req_d, '1, clk_i, rst_ni)
`FF(pending_q, pending_d, '0, clk_i, rst_ni)
`FF(max_addr_q, max_addr_d, '0, clk_i, rst_ni)



localparam int unsigned BytesPerWord = DataWidth >> 3;


//Hit check
always_comb begin
  
      max_addr = slv_req_i.ar.addr + ((slv_req_i.ar.len + 1) << (slv_req_i.ar.size));
      addr_end = (BurstSize << 3) + base_addr_q;
      if(max_addr <= addr_end && slv_req_i.ar.addr >= base_addr_q) begin
          hit = 1;

      end
      else begin
          hit = 0;

      end
  


end

always_comb begin
  //default values
  state_d = state_q;
  req_sram_d = req_sram_q;
  write_en_d = write_en_q;
  ar_valid_d = ar_valid_q;
  r_ready_d = r_ready_q;
  ar_ready_d = ar_ready_q;
  r_valid_d = r_valid_q;
  rid_d = rid_q;
  fill_cnt_d = fill_cnt_q;
  last_d = last_q;
  new_req_d = new_req_q;
  pending_d = pending_q;
  max_addr_d = max_addr_q;

  case(state_q)
    IDLE: begin

      ar_valid_d = 1'b0;
      r_valid_d = 1'b0;
      ar_ready_d = 1'b1;
      r_ready_d = 1'b0;
      req_sram_d = '0;
      fill_cnt_d = '0;
      pending_d = 1'b0;
      new_req_d = 1'b1;
      req_sram = 1'b0;

      max_addr_d = max_addr;
      
      if(slv_req_i.ar_valid && ar_ready_q) begin //replace slv_req_i.ar_valid with ar_valid_req when using bypass
        rid_d = slv_req_i.ar.id;
        req_len_d = ((slv_req_i.ar.len + 1) << slv_req_i.ar.size) / BytesPerWord;
        ar_ready_d = 1'b0;
    
        if(hit == 1'b1) begin
          state_d = SERVE;
          last_d = 1'b0;
        end
        else if(hit == 1'b0) begin
        state_d = REQUEST;
        base_addr_d = slv_req_i.ar.addr & ~ ((BurstSize << 3) -1); 
        ar_valid_d = 1'b1;

        end
        else begin
          state_d = IDLE;
        end
      end

      else begin
        addr_sram_d = '0;
        ar_ready_d = 1'b1;
      end

    end

    REQUEST: begin

      if(mst_resp_i.ar_ready) begin
        ar_valid_d = 1'b0;
      end //to comply with AXI protocol: valid goes low after handshakes happen

      r_valid_d = 1'b0;
      r_ready_d = 1'b1;
      write_en_d = 1'b1;

      //compute address to access sram 
      addr_sram_d = fill_cnt_q;

      //enable SRAM request when new data is coming: stay synchronized with r_valid
      req_sram = mst_resp_i.r_valid;  // req_i


      if(mst_resp_i.r.last == 1'b1) begin
        state_d = SERVE;
        fill_cnt_d = 0;
        addr_sram_d = ((max_addr_q - base_addr_q) >> 3) - req_len_q;
        last_d = 1'b0;

      end

      else if(r_ready_q && mst_resp_i.r_valid) begin
        fill_cnt_d = fill_cnt_q + 1;
        r_ready_d = 1'b0;
      end

    end

    SERVE: begin
      req_sram = req_sram_q;
      req_sram_d = 1'b0;
      ar_valid_d = 1'b0;
      ar_ready_d = 1'b0;  
      r_ready_d = 1'b0;
      write_en_d = 1'b0;

      if(req_len_q == 0) begin
          state_d = IDLE;
          r_valid_d = 1'b0;
          pending_d = 1'b0;
          req_sram_d = 1'b0;
          addr_sram_d = '0;
      end

      else begin
        //compute address to access sram 

  
        last_d = (req_len_q == 1) ? 1'b1 : 1'b0;

        if(new_req_q) begin

          new_req_d = 1'b0;  
          req_sram_d = 1'b1; 
          addr_sram_d = ((max_addr_q - base_addr_q) >> 3) - req_len_q;      

        end
        else begin
          req_sram_d = 1'b0;
        end

        pending_d = req_sram_q;

        r_valid_d = pending_q;

        if(r_valid_q && slv_req_i.r_ready) begin
          req_len_d = req_len_q - 1;
          new_req_d = 1'b1;
          addr_sram_d = addr_sram_q + 1;
        end

  
      end

    end

  endcase

end

tc_sram_impl #(
  .NumWords (BurstSize),
  .DataWidth (DataWidth),
  .NumPorts (1)
) i_sram_read (
  
  .clk_i   (clk_i),
  .rst_ni  (rst_ni),
  .req_i   (req_sram),
  .we_i    (write_en_q),
  .addr_i  (addr_sram_q),
  .wdata_i (mst_resp_i.r.data),
  .be_i    (8'b11111111),
  .rdata_o (slv_resp_o.r.data)
);


//BYPASS
/*always_comb begin

  if(slv_req_i.ar_valid && slv_req_i.ar.id != 6'h23) begin

    mst_req_o.ar_valid = slv_req_i.ar_valid;
    mst_req_o.ar = slv_req_i.ar;
    slv_resp_o.ar_ready = mst_resp_i.ar_ready;

    ar_valid_req = 1'b0;



    $display("Bypass in action!");


  end

  else begin

    mst_req_o.ar_valid = ar_valid_q;
    mst_req_o.ar.addr  = ar_addr_q;
    mst_req_o.ar.len   = 8'd127;
    mst_req_o.ar.size  = 3'd3;
    mst_req_o.ar.burst = 2'b01;
    mst_req_o.ar.id = 6'h23;
    slv_resp_o.ar_ready = ar_ready_q;

    ar_valid_req = slv_req_i.ar_valid;

  end

  if(mst_resp_i.r_valid && mst_resp_i.r.id != 6'h23 && state_q != SERVE) begin

    slv_resp_o.r = mst_resp_i.r;
    slv_resp_o.r_valid = mst_resp_i.r_valid;

  end

  else begin

    slv_resp_o.r_valid  = r_valid_q;
    slv_resp_o.r.id     = rid_q;
    slv_resp_o.r.last   = last_q;
    slv_resp_o.r.resp   = mst_resp_i.r.resp;
    slv_resp_o.r.user   = mst_resp_i.r.user;
    slv_resp_o.r.data   = rdata.r.data;

  end
end*/


assign  mst_req_o.ar_valid = ar_valid_q;
assign  mst_req_o.ar.addr  = base_addr_q;
assign  mst_req_o.ar.len   = BurstSize - 1;
assign  mst_req_o.ar.size  = 3'd3;
assign  mst_req_o.ar.burst = 2'b01;
assign  mst_req_o.ar.id = 6'h22;
assign  mst_req_o.ar.lock = 1'b0;
assign  mst_req_o.ar.prot = 3'b0;
assign  mst_req_o.ar.region = 4'b0;
assign  mst_req_o.ar.qos = 4'b0;
assign  mst_req_o.ar.cache = 4'h2;
assign  mst_req_o.ar.user =  2'h0;

assign  slv_resp_o.ar_ready = ar_ready_q;


assign  slv_resp_o.r_valid  = r_valid_q;
assign  slv_resp_o.r.id     = rid_q;
assign  slv_resp_o.r.last   = last_q;
assign  slv_resp_o.r.resp   = mst_resp_i.r.resp;
assign  slv_resp_o.r.user   = mst_resp_i.r.user;

assign mst_req_o.r_ready = 1'b1;




///////////////////////////WRITING BUFFER///////////////////////////////////

state_t state_w_d, state_w_q;

logic hit_w;

logic[AddrWidth-1:0] base_addr_w_d, base_addr_w_q, max_addr_w, addr_end_w, max_addr_w_d, max_addr_w_q;

//address to access sram

logic [SramAddrWidth-1:0] addr_sram_w, addr_sram_w_d, addr_sram_w_q;


//request length to manage narrow transfers
logic [$clog2(BurstSize):0] req_len_w_d, req_len_w_q;

//address id
logic [AxiIdWidth-1:0] b_id_d, b_id_q;

//SRAM control signals
logic req_sram_w;
logic req_sram_w_d, req_sram_w_q;
logic write_en_w_d, write_en_w_q, write_en_w;


logic aw_valid_d, aw_valid_q;
logic b_valid_d, b_valid_q;
logic aw_ready_d, aw_ready_q;
logic w_valid_d, w_valid_q;
logic w_last_d, w_last_q;
logic b_ready_d, b_ready_q;
logic w_valid_in_d, w_valid_in_q;

logic new_req_w_d, new_req_w_q;

logic pending_w_d, pending_w_q;

logic [9:0] timer_d, timer_q;

logic timeout;

//validity array
logic [BurstSize-1:0] validity_d, validity_q;  

tc_sram_impl #(
  .NumWords (BurstSize),
  .DataWidth (DataWidth),
  .NumPorts (1)
) i_sram_write (
  
  .clk_i   (clk_i),
  .rst_ni  (rst_ni),
  .req_i   (req_sram_w),
  .we_i    (write_en_w),
  .addr_i  (addr_sram_w),
  .wdata_i (slv_req_i.w.data),
  .be_i    (byte_en),
  .rdata_o (mst_req_o.w.data)
);

//registers
`FF(state_w_q, state_w_d, IDLE, clk_i, rst_ni)
`FF(aw_valid_q, aw_valid_d, 1'b0, clk_i, rst_ni)
`FF(b_valid_q, b_valid_d, 1'b0, clk_i, rst_ni)
`FF(req_sram_w_q, req_sram_w_d, 1'b0, clk_i, rst_ni)
`FF(req_len_w_q, req_len_w_d, '0, clk_i, rst_ni)
`FF(aw_ready_q, aw_ready_d, '0, clk_i, rst_ni)
`FF(b_ready_q, b_ready_d, '0, clk_i, rst_ni)
`FF(write_en_w_q, write_en_w_d, '0, clk_i, rst_ni)
`FF(b_id_q, b_id_d, '0, clk_i, rst_ni)
`FF(base_addr_w_q, base_addr_w_d, '0, clk_i, rst_ni)
`FF(addr_sram_w_q, addr_sram_w_d, '0, clk_i, rst_ni)
`FF(new_req_w_q, new_req_w_d, '1, clk_i, rst_ni)
`FF(pending_w_q, pending_w_d, '0, clk_i, rst_ni)
`FF(max_addr_w_q, max_addr_w_d, '0, clk_i, rst_ni)
`FF(timer_q, timer_d, '0, clk_i, rst_ni)
`FF(validity_q, validity_d, '0, clk_i, rst_ni)
`FF(w_valid_q, w_valid_d, '0, clk_i, rst_ni)
`FF(w_last_q, w_last_d, '0, clk_i, rst_ni)
`FF(w_valid_in_q, w_valid_in_d, '0, clk_i, rst_ni)


//Hit check
always_comb begin
  
      max_addr_w = slv_req_i.aw.addr + ((slv_req_i.aw.len + 1) << (slv_req_i.aw.size));
      addr_end_w = (BurstSize << 3) + base_addr_w_q;
      if(max_addr_w < addr_end_w && slv_req_i.aw.addr >= base_addr_w_q) begin
          hit_w = 1;

      end
      else begin
          hit_w = 0;

      end

end

always_comb begin
  //default values
  state_w_d = state_w_q;
  req_sram_w_d = req_sram_w_q;
  write_en_w_d = write_en_w_q;
  aw_valid_d = aw_valid_q;
  b_ready_d = b_ready_q;
  aw_ready_d = aw_ready_q;
  b_valid_d = r_valid_q;
  b_id_d = b_id_q;
  validity_d = validity_q;
  new_req_w_d = new_req_w_q;
  pending_w_d = pending_w_q;
  max_addr_w_d = max_addr_w_q;
  w_valid_d = w_valid_q;
  w_last_d = w_last_q;;
  slv_resp_o.w_ready = 1'b0;


  case (state_w_q)

    IDLE: begin

      aw_valid_d = 1'b0;
      b_valid_d = 1'b0;
      aw_ready_d = 1'b1;
      b_ready_d = 1'b1;
      req_sram_w_d = '0;
      pending_w_d = 1'b0;
      new_req_w_d = 1'b1;
      req_sram_w = 1'b0;
      w_valid_d = 1'b0;
      slv_resp_o.w_ready = 1'b0;

      max_addr_w_d = max_addr_w;

      //TIMER to go to REQUEST
      timer_d = timer_q + 1;

      if(timer_q >= CoalWindow) begin
        timer_d = '0;
        if(validity_q) begin
          state_w_d = REQUEST;
          timeout = 1'b1;
          //base_addr_w_d = '0;
          aw_valid_d = 1'b1;
          aw_ready_d = 1'b0;
          new_req_w_d = 1'b1;
        end
      end
      else 
        timeout = 1'b0;
      
      if(slv_req_i.aw_valid && aw_ready_q) begin //replace slv_req_i.ar_valid with ar_valid_req when using bypass
        b_id_d = slv_req_i.aw.id;
        req_len_w_d = ((slv_req_i.aw.len + 1) << slv_req_i.aw.size) / BytesPerWord;
        aw_ready_d = 1'b0;
    
        if(hit_w == 1'b1) begin
          state_w_d = SERVE;
          timer_d = 0;
       
        end
        else if(hit_w == 1'b0) begin 
          base_addr_w_d = slv_req_i.aw.addr & ~ ((BurstSize << 3) -1);
          if(validity_q) begin
            state_w_d = REQUEST;
            aw_valid_d = 1'b1;
            timeout = 1'b0;
            new_req_w_d = 1'b1;
          end
          else begin
            state_w_d = SERVE;
          end

        end
        else begin
          state_w_d = IDLE;
        end
      end

      else if(slv_req_i.aw_valid) begin
        addr_sram_w_d = '0;
      end

      else begin
        addr_sram_w_d = '0;
      end


    end


    REQUEST: begin //I still call it request, because I am requesting to write to hyperbus
      
      //normally write all bytes
      mst_req_o.w.strb = 8'b11111111;

      if(mst_resp_i.aw_ready) begin
        aw_valid_d = 1'b0;
      end //to comply with AXI protocol: valid goes low after handshakes happen

      b_valid_d = 1'b0;
      b_ready_d = 1'b1;
      write_en_w_d = 1'b0;

      addr_sram_w = addr_sram_w_q;
      req_sram_w = req_sram_w_q;
      write_en_w = write_en_w_q;

      
      //compute "last" bit
      w_last_d = (addr_sram_w_q == BurstSize-1) ? 1'b1 : 1'b0;

      req_sram_w_d = new_req_w_q; 

      if(new_req_w_q) begin
        new_req_w_d = 1'b0;
      end

      if(w_valid_q && !mst_resp_i.w_ready) begin
        w_valid_d = 1'b1;
      end
      else begin
        w_valid_d = req_sram_w_q;
      end

      if(validity_q[addr_sram_w_q] != 1'b1) begin
        //when not valid don't write anything
        mst_req_o.w.strb = 8'b0;
      end
 
      
      if(w_valid_q && mst_resp_i.w_ready) begin
        addr_sram_w_d = addr_sram_w_q + 1; //advance after handshake
        w_valid_d = 1'b0;
        req_sram_w_d = 1'b0;
        validity_d[addr_sram_w_q] = 1'b0;
        new_req_w_d = 1'b1;
      end

      //enable SRAM request when new data is coming: stay synchronized with r_valid
  
      if(w_last_q == 1'b1 && w_last_d == 1'b0) begin
        if(timeout) begin
          state_w_d = IDLE;
          //base_addr_w_d = '0;
        end
        else begin
          state_w_d = SERVE;
          addr_sram_w_d = ((max_addr_w_q - base_addr_w_q) >> 3) - req_len_w_q;
        end
      end

    end

    SERVE: begin
      
      //req_sram_w = req_sram_w_q;
      //addr_sram_w = addr_sram_w_q;
      //req_sram_w_d = slv_req_i.w_valid;
      aw_valid_d = 1'b0;  
      b_ready_d = 1'b0;
      write_en_w = slv_req_i.w_valid;

      req_sram_w = slv_req_i.w_valid;
      slv_resp_o.w_ready = slv_req_i.w_valid;
      addr_sram_w = ((max_addr_w_q - base_addr_w_q) >> 3) - req_len_w_q; 
      validity_d[addr_sram_w] = 1'b1; //if we got to this point we wrote on this word

      if(slv_req_i.w_valid) begin
        byte_en = slv_req_i.w.strb;
      end

      if(slv_req_i.w.last && slv_req_i.w_valid) begin
          state_w_d = IDLE;
          b_valid_d = 1'b1;
          pending_w_d = 1'b0;
          req_sram_w_d = 1'b0;
          addr_sram_w_d = '0;
      end

      else begin
        //compute address to access sram 

        b_valid_d = 1'b0;
        state_w_d = SERVE;
        //addr_sram_w_d = addr_sram_w_q + (slv_req_i.w_valid & w_ready_q); 
        req_len_w_d = req_len_w_q - (slv_req_i.w_valid & slv_resp_o.w_ready);    
      
      end 


    end


  endcase


end

assign w_valid_in_d = slv_req_i.w_valid;

assign  mst_req_o.aw_valid = aw_valid_q;
assign  mst_req_o.aw.addr  = base_addr_w_q;
assign  mst_req_o.aw.len   = BurstSize - 1;
assign  mst_req_o.aw.size  = 3'd3;
assign  mst_req_o.aw.burst = 2'b01;
assign  mst_req_o.aw.id = 6'h22;
assign  mst_req_o.aw.lock = 1'b0;
assign  mst_req_o.aw.prot = 3'b0;
assign  mst_req_o.aw.region = 4'b0;
assign  mst_req_o.aw.qos = 4'b0;
assign  mst_req_o.aw.cache = 4'h2;
assign  mst_req_o.aw.atop = 6'h00;
assign  mst_req_o.aw.user =  2'h0;

assign slv_resp_o.aw_ready = aw_ready_q;

assign mst_req_o.w_valid = w_valid_q;
assign mst_req_o.w.last = w_last_q;
assign mst_req_o.w.user = 2'h0;

//assign slv_resp_o.w_ready = w_ready_q;

assign slv_resp_o.b_valid = b_valid_q;
assign slv_resp_o.b.id = b_id_q;
assign slv_resp_o.b.resp = 2'h0;
assign slv_resp_o.b.user = 2'h0;
assign mst_req_o.b_ready = b_ready_q;



endmodule