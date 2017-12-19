/* Copyright 2017 Tymoteusz Blazejczyk
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

`include "logic.svh"

/* Module: logic_axi4_stream_buffered
 *
 * Improve timings between modules by adding register to ready signal path from
 * tx to rx ports and it keeps zero latency bus transcation on both sides.
 *
 * Parameters:
 *  TDATA_BYTES - Number of bytes for tdata signal.
 *  TDEST_WIDTH - Number of bits for tdest signal.
 *  TUSER_WIDTH - Number of bits for tuser signal.
 *  TID_WIDTH   - Number of bits for tid signal.
 *
 * Ports:
 *  aclk        - Clock.
 *  areset_n    - Asynchronous active-low reset.
 *  rx          - AXI4-Stream interface.
 *  tx          - AXI4-Stream interface.
 */
module logic_axi4_stream_buffered #(
    int TDATA_BYTES = 1,
    int TDEST_WIDTH = 1,
    int TUSER_WIDTH = 1,
    int TID_WIDTH = 1
) (
    input aclk,
    input areset_n,
    `LOGIC_MODPORT(logic_axi4_stream_if, rx) rx,
    `LOGIC_MODPORT(logic_axi4_stream_if, tx) tx
);
    localparam TLAST_WIDTH = 1;
    localparam TDATA_WIDTH = TDATA_BYTES * 8;
    localparam TSTRB_WIDTH = TDATA_BYTES;
    localparam TKEEP_WIDTH = TDATA_BYTES;

    localparam WIDTH = TUSER_WIDTH + TDEST_WIDTH + TID_WIDTH + TLAST_WIDTH +
        TKEEP_WIDTH + TSTRB_WIDTH + TDATA_WIDTH;

    logic [WIDTH-1:0] rx_tdata;
    logic [WIDTH-1:0] tx_tdata;

    always_comb rx_tdata = {rx.tuser, rx.tdest, rx.tid, rx.tlast, rx.tkeep,
        rx.tstrb, rx.tdata};

    always_comb {tx.tuser, tx.tdest, tx.tid, tx.tlast, tx.tkeep,
        tx.tstrb, tx.tdata} = tx_tdata;

    logic_basic_buffered #(
        .WIDTH(WIDTH)
    )
    unit (
        .rx_tvalid(rx.tvalid),
        .rx_tready(rx.tready),
        .tx_tvalid(tx.tvalid),
        .tx_tready(tx.tready),
        .*
    );
endmodule
