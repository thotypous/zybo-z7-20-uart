import ConfigReg::*;
import FIFOF::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;

import GetPut_Aux::*;
import Semi_FIFOF::*;

import AXI4_Types::*;


typedef 12   Wd_Slave_Id;
typedef 32   Wd_Addr;
typedef 32   Wd_Slave_Data;
typedef  0   Wd_User;

interface AXI4_IFC;
    interface AXI4_Slave_IFC  #(Wd_Slave_Id,  Wd_Addr, Wd_Slave_Data,  Wd_User)  slave;
    (*always_ready*)
    method Bit#(1) irq;
endinterface


typedef Bit#(Wd_Addr) Addr;


interface AXI4_Adapter;
    interface AXI4_IFC axi;
endinterface

module mkAXI4_Adapter (AXI4_Adapter);
    Reg#(Bit#(1)) test_state <- mkReg(1'b0);
    Reg#(Bit#(1)) irq_status <- mkReg(1'b0);

    AXI4_Slave_Xactor_IFC #(Wd_Slave_Id,
                            Wd_Addr,
                            Wd_Slave_Data,
                            Wd_User) slave_xactor  <- mkAXI4_Slave_Xactor;

    rule slave_rd;
        let rd_addr <- pop_o(slave_xactor.o_rd_addr);

        Bit#(Wd_Slave_Data) data = case (rd_addr.araddr[11:2])
            10'd0: 32'hbadc0ffe;
            10'd1: 32'hbadc0fe0 | extend(test_state);
            default: 32'hdeadbeef;
        endcase;

        AXI4_Rd_Data#(Wd_Slave_Id, Wd_Slave_Data, Wd_User)
        rd_data = AXI4_Rd_Data {rid:   rd_addr.arid,
                                rdata: data,
                                rresp: axi4_resp_okay,
                                rlast: True,
                                ruser: rd_addr.aruser};

        slave_xactor.i_rd_data.enq(rd_data);
    endrule

    rule slave_wr;
        let wr_addr <- pop_o(slave_xactor.o_wr_addr);
        let wr_data <- pop_o(slave_xactor.o_wr_data);

        let data = wr_data.wdata;

        case (wr_addr.awaddr[11:2])
            10'd0: test_state <= data[0];
            10'd1: irq_status <= 1'b0;
            10'd2: irq_status <= 1'b1;
        endcase

        AXI4_Wr_Resp#(Wd_Slave_Id, Wd_User)
        wr_resp = AXI4_Wr_Resp {bid:   wr_addr.awid,
                                bresp: axi4_resp_okay,
                                buser: wr_addr.awuser};

        slave_xactor.i_wr_resp.enq(wr_resp);
    endrule

    interface AXI4_IFC axi;
        interface slave  = slave_xactor.axi_side;
        method irq = irq_status;
    endinterface
endmodule
