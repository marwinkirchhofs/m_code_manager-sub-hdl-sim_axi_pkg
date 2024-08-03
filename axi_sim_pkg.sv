`timescale 1ns/1ps

package axi_sim_pkg;

    import util_pkg::print_test_start;
    import util_pkg::print_test_result;
    import util_pkg::print_tests_stats;

    /*
    * performance statistics for one AXI transaction - can be read-only, 
        * write-only, or write-read test. For accumulating multiple bursts, an 
        * add function is defined.
    * -1 as default value for all fields, because not all fields are applicable 
    *  in every transaction (like time_write is pointless when reading). So -1 
*  gives a clear distinction between valid and invalid data.
    */
    class cls_axi_transaction_stats;
        // posedge write addr/data handshake -> negedge last resp handshake
        time                time_total          = -1;
        // posedge write addr/data handshake -> negedge write resp handshake
        time                time_write          = -1;
        // posedge read addr handshake -> negedge read resp handshake
        time                time_read           = -1;
        // negedge write resp handshake -> posedge read addr handshake
        time                time_read_to_write  = -1;
        // valid axi data bits - meaning strb is taken into account
        int                 num_axi_words       = 0;
        int                 num_axi_bits        = 0;
        // number of "effective" transmitted bits (not taking into account axi
        // padding)
        int                 num_user_bits       = 0;

        function new();
            this.time_total                     = -1;
            this.time_write                     = -1;
            this.time_read                      = -1;
            this.time_read_to_write             = -1;
            this.num_axi_words                  = 0;
            this.num_axi_bits                   = 0;
            this.num_user_bits                  = 0;
        endfunction // new

        function void zero();
            this.time_total                     = 0;
            this.time_write                     = 0;
            this.time_read                      = 0;
            this.time_read_to_write             = 0;
            this.num_axi_words                  = 0;
            this.num_axi_bits                   = 0;
            this.num_user_bits                  = 0;
        endfunction // zero

        function void add (cls_axi_transaction_stats ats);
            this.time_total         = this.time_total           + ats.time_total;
            this.time_write         = this.time_write           + ats.time_write;
            this.time_read          = this.time_read            + ats.time_read;
            this.time_read_to_write = this.time_read_to_write   + ats.time_read_to_write;
            this.num_axi_words      = this.num_axi_words        + ats.num_axi_words;
            this.num_axi_bits       = this.num_axi_bits         + ats.num_axi_bits;
            this.num_user_bits      = this.num_user_bits        + ats.num_user_bits;
        endfunction // add
        
        function void print_short();
            $display("\t**** transaction stats ****");
            $display("\ttotal: %0t - read: %0t - write: %0t - read-to-write: %0t",
                time_total, time_read, time_write, time_read_to_write);
        endfunction // print_short

        /*
        * additionally takes into consideration the number of axi words, and 
        * prints a time per word/beat
        */
        // TODO: it might be interesting if this function can distinguish 
        // between read, write, and write-read -> could be based on valid data 
        // being available
        function void print_long();
            this.print_short();
            if (num_axi_words == 0) begin
                $warning("num_axi_words = 0! Not printing time per word...");
            end else begin
                $display("\tnum axi words: %0d - avg time per axi word: %t",
                    num_axi_words, time_total/num_axi_words);
                $display("\taxi throughput: %0f GB/s - user throughput: %0f GB/s",
                    real'(num_axi_bits)/8/time_total, real'(num_user_bits)/8/time_total);
            end
        endfunction // print_long

    endclass // axi_transaction_stats

    /*
    * pseudo constrained randomization class for test data - all the freely 
    * available tools don't support actual constrained randomization. This class 
* still provides a way of getting a randomized dynamic 2-dimensional regular 
* arary with the individual vectors of the array all randomized.
    * Zero-initialization is possible as well, for data type consistency between 
    * different test data objects (for example when one is for writing and the 
* other is read-back, to be compared afterwards)
    */
    class cls_test_data;

        logic data [][];

        function new (input int num_words, input int bitwidth,
            input bit randomize_data=0);
            data = new[num_words];
            foreach (data[i]) data[i] = new[bitwidth];
            initialize(randomize_data);
        endfunction // new

        function void initialize(input bit randomize_data=0);
            if (randomize_data) begin
                this.randomize_data();
            end else begin
                this.set_zero();
            end
        endfunction // new

        function void randomize_data();
            foreach (data[i,j]) data[i][j] = $random;
        endfunction // randomize_data

        function void set_zero();
            foreach (data[i,j]) data[i][j] = 0;
        endfunction // set_zero

        /*
        * number of data words
        */
        function int get_len();
            return $size(data);
        endfunction // get_len

        /*
        * bitwidth of data words
        */
        function int get_size();
            return $size(data[0]);
        endfunction // get_size

        /*
        * test for equality with another cls_test_data object
        */
        function bit equals (cls_test_data data_compare);
            return data == data_compare.data;
        endfunction // equals


        /*
        * print the generated data in a 64-bit casted hex format
        * (obviously will fail in some way if the data words are wider than 64 
        * bits, but it does the job for quick debugging)
        */
        function void print64();
            bit [63:0] data_packed;
            for (int i=0; i<$size(data); i++) begin
                data_packed = {>>64{data[i]}};
                data_packed = {<<{data_packed}};
                $display("data item %0d: %h", i, data_packed);
            end
        endfunction // print64

        /*
        * print the generated data in a 256-bit casted hex format
        * (obviously will fail in some way if the data words are wider than 64 
        * bits, but it does the job for quick debugging)
        */
        function void print256();
            bit [255:0] data_packed;
            for (int i=0; i<$size(data); i++) begin
                data_packed = {>>256{data[i]}};
                data_packed = {<<{data_packed}};
                $display("data item %0d: %h", i, data_packed);
            end
        endfunction // print256

    endclass // cls_test_data

    /*
    * changes AXI3 -> AXI4
    * * w_id is basically deprecated in AXI4
    * * ax_lock signals 2-bit to 1-bit
    */

    //----------------------------------------------------------
    // PARAMETERS
    //----------------------------------------------------------

    //----------------------------
    // PROTOCOL CONSTANTS
    //----------------------------
    // AXI4_BIT_* bit index in respective signal
    // AXI4_* - bit vector constant
    
    parameter                   AXI4_BURST_FIXED        = 'b00;
    parameter                   AXI4_BURST_INCR         = 'b01;
    parameter                   AXI4_BURST_WRAP         = 'b10;

    parameter                   AXI4_RESP_OKAY          = 'b00;
    parameter                   AXI4_RESP_EXOKAY        = 'b01;
    parameter                   AXI4_RESP_SLVERR        = 'b10;
    parameter                   AXI4_RESP_DECERR        = 'b11;

    parameter                   AXI4_BIT_CACHE_BUFFER   = 0;
    parameter                   AXI4_BIT_CACHE_MODIFY   = 1;    // CACHE IN AXI3
    parameter                   AXI4_BIT_CACHE_READALLOC    = 2;
    parameter                   AXI4_BIT_CACHE_WRITEALLOC   = 3;

    parameter                   AXI4_BIT_PROT_PRIVIL    = 0;
    parameter                   AXI4_BIT_PROT_SECURE    = 1;
    parameter                   AXI4_BIT_PROT_DATA      = 2;

    localparam                  AXI4_MAX_BURST_LEN      = 256;
    localparam                  AXI3_MAX_BURST_LEN      = 16;

    //----------------------------
    // SIGNAL DEFAULTS
    //----------------------------
    // * some defaults can only be defined as single-bit here although they are 
    // multi-bit, because the signals have dynamic width
    // * *_size cannot be done here because it fully depends on the databus 
    // width

    parameter                   AXI4_DEFAULT_ID         = 1'b0;
    parameter                   AXI4_DEFAULT_REGION     = 4'b0;
    parameter                   AXI4_DEFAULT_LEN        = 8'b0;
    parameter                   AXI4_DEFAULT_BURST      = AXI4_BURST_INCR;
    parameter                   AXI4_DEFAULT_LOCK       = 0;
    parameter                   AXI4_DEFAULT_CACHE      = 4'b0;
    parameter                   AXI4_DEFAULT_QOS        = 4'b0;
    parameter                   AXI4_DEFAULT_STRB       = 1'b1;
    parameter                   AXI4_DEFAULT_BRESP      = AXI4_RESP_OKAY;

    //----------------------------
    // VERBOSITY LEVELS
    //----------------------------

    localparam                  VERBOSITY_OPERATION     = 1;
    localparam                  VERBOSITY_DATA          = 2;
    localparam                  VERBOSITY_PROTOCOL      = 3;


    //----------------------------------------------------------
    // CLASS
    //----------------------------------------------------------
    
    /*
    *
    * Available read and write tasks:
    * * normal operation
    *     * read/write_words
    *       user side function with an arbitrary-sized (but regular) data object 
    *       - internally splits up data into suitable burst writes
    *     * read/write_burst
    *       pure protocol operation function - receives data/requests in 
    *       AXI-language and executes a burst, with the option to let a second 
    *       burst follow right-away
    * * test
    *     * test_rand_write_read
    *       use read/write_words to perform a data correctness test - internally 
    *       generate randomized data according to requested number and size of 
    *       items
    * * benchmark
    *     * benchmark_read/write
    *       use read/write words to perform an operation with the requested 
    *       parameters, but only return the accumulated transaction stats, not 
    *       the data
    *
    * TODO: think about axi version-dependent assertions for burst length and 
    * burst size in the read/write_burst tasks
    */
    class cls_axi_traffic_gen_sim #(
        AXI_VERSION="AXI4",
        ADDR_WIDTH=32,
        DATA_WIDTH=32,
        ID_WIDTH=0,
        USER_WIDTH=0,
        T_SETUP=1,
        T_CTOQ=2
        );
        // TODO: implement AXI3 and AXI4_LITE (however, that might require 
        // inheritance after all to do it nicely, because the virtual member 
        // interface is a different one and this is not python. Maybe the more 
        // "logical" idea, instead of inheritance: Can't you just parameterize 
        // the interface with the AXI version?

        virtual ifc_axi4 #(
                .ADDR_WIDTH (ADDR_WIDTH),
                .DATA_WIDTH (DATA_WIDTH),
                .ID_WIDTH   (ID_WIDTH),
                .USER_WIDTH (USER_WIDTH),
                .T_SETUP    (T_SETUP),
                .T_CTOQ     (T_CTOQ)
            ) if_axi;

        const int               MAX_BURST_LEN;

        //----------------------------
        // CREATION/INITIALIZATION
        //----------------------------

        function new(
            virtual ifc_axi4 #(
                    .ADDR_WIDTH (ADDR_WIDTH),
                    .DATA_WIDTH (DATA_WIDTH),
                    .ID_WIDTH   (ID_WIDTH),
                    .USER_WIDTH (USER_WIDTH),
                    .T_SETUP    (T_SETUP),
                    .T_CTOQ     (T_CTOQ)
                ) if_axi);
            this.if_axi = if_axi;
            this.init();
            case (AXI_VERSION)
                "AXI4": this.MAX_BURST_LEN = AXI4_MAX_BURST_LEN;
                "AXI3": this.MAX_BURST_LEN = AXI3_MAX_BURST_LEN;
                default: $error("Invalid AXI_VERSION: %s", AXI_VERSION);
            endcase
        endfunction // new

        /*
        * assign default values to all master-driven axi interface signals
        */
        function void init();
            // standard defaults (as per specification)
            if_axi.awid                     = {DATA_WIDTH{AXI4_DEFAULT_ID}};
            if_axi.arid                     = {DATA_WIDTH{AXI4_DEFAULT_ID}};
            if_axi.wid                      = {DATA_WIDTH{AXI4_DEFAULT_ID}};
            if_axi.awregion                 = AXI4_DEFAULT_REGION;
            if_axi.arregion                 = AXI4_DEFAULT_REGION;
            if_axi.awlen                    = AXI4_DEFAULT_LEN;
            if_axi.arlen                    = AXI4_DEFAULT_LEN;
            if_axi.awburst                  = AXI4_DEFAULT_BURST;
            if_axi.arburst                  = AXI4_DEFAULT_BURST;
            if_axi.awlock                   = AXI4_DEFAULT_LOCK;
            if_axi.arlock                   = AXI4_DEFAULT_LOCK;
            if_axi.awcache                  = AXI4_DEFAULT_CACHE;
            if_axi.arcache                  = AXI4_DEFAULT_CACHE;
            if_axi.awqos                    = AXI4_DEFAULT_QOS;
            if_axi.arqos                    = AXI4_DEFAULT_QOS;
            if_axi.wstrb                    = {(DATA_WIDTH/8){AXI4_DEFAULT_STRB}};

            // "operation signal" defaults (more like clean initialization)
            if_axi.awaddr                   = '0;
            if_axi.araddr                   = '0;
            if_axi.awsize                   = '0;
            if_axi.arsize                   = '0;
            if_axi.awprot                   = AXI4_BIT_PROT_DATA;
            if_axi.arprot                   = AXI4_BIT_PROT_DATA;
            if_axi.awuser                   = '0;
            if_axi.aruser                   = '0;
            if_axi.wuser                    = '0;
            if_axi.awvalid                  = 0;
            if_axi.wvalid                   = 0;
            if_axi.arvalid                  = 0;
            if_axi.rready                   = 0;
            if_axi.bready                   = 0;

            if_axi.wlast                    = 0;
            if_axi.wdata                    = '0;
        endfunction // init

        //----------------------------
        // UTIL
        //----------------------------

        /*
        * allow for data element width to not be an 8-bit multiple
        * 
    * retuns: smallest power-of-2 byte width that can accomodate bitwidth 
    * because burst_size has to be a power-of-2)
        */
        protected function int int_burst_size_from_bitwidth(input int bitwidth);
            return 1<<($clog2(int'($ceil(real'(bitwidth)/8))));
        endfunction // int_burst_size_from_bitwidth

        //----------------------------
        // PLAIN READ/WRITE
        //----------------------------
        
        // SINGLE BURSTS

        task write_burst();
        endtask

        /*
        * perform a (INCR) write burst from a dynamic (regular) array 'data'
        * - burst length is the number of elements in data
        * - beat size is the size of each element in data
        * strb is automatically derived from DATA_WIDTH and beat size
        * TODO: allow specifying id, region, lock, cache, prot (and maybe qos, 
            * while you're at it)
        * TODO: support non-INCR burst
        */
        task write_bursts(
            input logic [ADDR_WIDTH-1:0] base_address,
            input logic data [][][],
            output logic [1:0] resp [],
            input cls_axi_transaction_stats ats,
            input allow_outstanding_transactions = 1,
            input wait_cycle = 1
        );

            logic [ADDR_WIDTH-1:0] address = base_address;

            const int num_bursts = $size(data);
            int burst_len_addr;
            int burst_len_data;
            int int_burst_size;
            int burst_item = 0;
            // byte lane for the LSB for transactions that are narrower than the 
            // bus width
            int start_lane_idx = 0;

            // synchroniation variables for allow_outstanding_transactions == 0
            bit addr_handshake_completed [] = new[num_bursts];
            bit data_completed [] = new[num_bursts];

            // helper variable when casting from dynamic (unpacked) array data 
            // to packed if_axi.wdata - for some reason it doesn't work to cast 
            // to DATA_WIDTH and do right-justifying in one step with two stream 
            // operators (result was the correct meaningful bit order, but 
            // left-justified), but it works in two steps with an intermediary 
            // variable.
            logic [DATA_WIDTH-1:0] data_packed;

            time time_start;

            // ensure zero-initialization
            for (int i=0; i<num_bursts; i++) begin
                addr_handshake_completed[i] = 0;
                data_completed[i] = 0;
            end

            ats.zero();

            if (wait_cycle) @(posedge if_axi.cb);
            time_start = $time;

            if (`VERBOSITY >= VERBOSITY_OPERATION)
                $display("[%0t] **** AXI WRITE BURST OPERATION ****", $time);
//             if (`VERBOSITY >= VERBOSITY_PROTOCOL) begin
//                 $display("burst length: %0d - burst size: %0d (DATA_WIDTH: %0d)",
//                     burst_len, int_burst_size, DATA_WIDTH);
//             end

            fork

            begin
                if_axi.cb.awvalid <= 1;
                for (int transaction=0; transaction<num_bursts; transaction++) begin
                    burst_len_addr = $size(data[transaction]);
                    int_burst_size = $size(data[transaction][0])/8;
                    // TODO: AXI_VERSION dependent
                    assert (int_burst_size inside {1, 2, 4, 8, 16, 32, 64, 128});
                    assert (int_burst_size <= DATA_WIDTH);

                    if_axi.cb.awaddr <= address;
                    if_axi.cb.awlen <= burst_len_addr-1;
                    if_axi.cb.awsize <= $clog2(int_burst_size);
                    if_axi.cb.awvalid <= 1;

                    @(posedge if_axi.cb);
                    wait(if_axi.cb.awready);

                    addr_handshake_completed[transaction] = 1;

                    if (~allow_outstanding_transactions) begin
                        if_axi.cb.arvalid <= 0;
                        wait(data_completed[transaction]);
                    end

                    address += burst_len_addr * int_burst_size;

                end
                if_axi.cb.awvalid <= 0;
                if_axi.cb.awlen <= '0;
                if_axi.cb.awsize <= '0;
                if_axi.cb.awaddr <= '0;
            end

            // DATA TRANSMISSIONS
            begin: fork_data
                for (int transaction=0; transaction<num_bursts; transaction++)
                begin: transactions

                    // TODO: I think that by protocol it was not allowed to wait 
                    // for the address handshake, so you should exclude the 
                    // option entirely. Check that once it's not close to 
                    // midnight.
//                     if (wait_address_handshake) wait(addr_handshake_completed[transaction]);

                    start_lane_idx = 0;
                    burst_len_data = $size(data[transaction]);
                    int_burst_size = $size(data[transaction][0])/8;

                    for (int burst_item=0; burst_item<burst_len_data; burst_item++)
                    begin: current_burst

                        // (why 2-step? see comment for data_packed)
                        data_packed = {>>DATA_WIDTH{data[transaction][burst_item]}};
                        data_packed = {<<{data_packed}};
                        if_axi.cb.wdata <= data_packed<<(start_lane_idx*8);
                        if_axi.cb.wstrb <= ((1'b1<<int_burst_size) - 1) << start_lane_idx;
                        if_axi.cb.wvalid <= 1;

                        if (burst_item == burst_len_data-1) if_axi.cb.wlast <= 1;

                        @(posedge if_axi.cb);
                        wait(if_axi.cb.wready);
                        if (`VERBOSITY >= VERBOSITY_DATA) begin
                            $display("[%0t] writing data beat %3d: %h",
                                    $time, burst_item, if_axi.wdata);
                            $display("start_lane: %0d, wstrb: %b", start_lane_idx, if_axi.wstrb);
                        end

                        // TODO: check if the start lane index always starts at 0, 
                        // or if that depends on the address (meaning if the address 
                        // is not bus width-aligned, you would start at a different 
                        // lane respectively)

                        // (this should be safe to not overflow the bus width 
                        // (start_lane_idx+int_burst_size), because int_burst_size 
                        // by specification is a power of 2, so it always divides 
                        // DATA_WIDTH/8)
                        start_lane_idx = (start_lane_idx+int_burst_size) % (DATA_WIDTH/8);
                    end // current_burst

                    if_axi.cb.wvalid <= 0;
                    if_axi.cb.wlast <= 0;
                    if_axi.cb.wstrb <= '0;
                    if_axi.cb.wdata <= '0;

                    // TODO: check if clock cycle waiting is necessary, or if 
                    // otherwise it's maybe allowed to already assert bready 
                    // during the last data beat
                    if_axi.cb.bready <= 1;
                    @(posedge if_axi.cb);
                    wait(if_axi.cb.bvalid);
                    resp[transaction] = if_axi.cb.bresp;
                    if (`VERBOSITY >= VERBOSITY_PROTOCOL) begin
                        $display("[%0t] write response received", $time);
                    end
                    if_axi.cb.bready <= 0;

                    ats.num_axi_words += burst_len_data;
                    ats.num_axi_bits += burst_len_data * int_burst_size * 8;
                    // TODO: maybe user bits shouldn't be set by this function at all -
                    // definitely it should be set by write_words once that is
                    // implemented
                    ats.num_user_bits += burst_len_data * int_burst_size * 8;

                end // transactions
            end // fork data

            join

            ats.time_total = $time - time_start;
            ats.time_write = $time - time_start;

        endtask // write_burst

        /*
        * distinction between read_words and read_burst:
        * - read_burst is a pure AXI protocol, and it returns data of 
        *   DATA_WIDTH. It performs exactly one burst. It is written such that 
        *   one can have consecutive bursts without a rready deassertion.
        * - read_words is more of a "user-side" function. It returns data of 
        *   arbitrary bitwidth, but internally it uses read_burst and translates 
        *   the results from AXI-valid data widths to the user-given bitwidth.  
            *   (assuming that the data has also been written this way - it sets 
            *   the burst size to be suitable and as small as possible)
        */

        task read_burst();
            // TODO: make that a wrapper to read_bursts, in case you only want 
            // to transmit one burst - such that you don't have to deal with the 
            // additional data dimension in that case
        endtask

        // TODO: add something like a "transfer ok" field, which reports an 
        // early or missing rlast (and maybe other things that pop up along the 
        // way to come)
        // TODO: for some reason data can't be a ref because actual and formal 
        // type... possible reason: as a dynamic array, it's an object, not 
        // a signal, and objects are always reference
        //
        // - data: dynamic array [burst_len[i]][burst_size_bits[i]][num_bursts]
        //     - burst_len[i] and burst_size_bits[i] don't have to be constant, 
        //     but they need to be valid for the AXI_VERSION
        // - allow_outstanding_transactions: allows to perform address 
        // handshakes right when the slave is ready. If disabled, every address 
        // handshake waits for the previous burst to be completed.
        // - wait_address_handshake: waits for the address handshake to complete 
        // before asserting rready. Disable for consecutive bursts.
        // - wait_cycle: if 1, wait for axi clock posedge for a well-defined 
        // starting state. Disable for consecutive bursts.
        task read_bursts(
            input logic [ADDR_WIDTH-1:0] base_address,
            ref logic data [][][],
            output logic [1:0] resp [],
            input cls_axi_transaction_stats ats,
            input allow_outstanding_transactions = 1,
            input wait_address_handshake = 1,
            input wait_cycle = 1
            );

            logic [ADDR_WIDTH-1:0] address = base_address;

            const int num_bursts = $size(data);
            int burst_len_addr;
            int burst_len_data;
            int int_burst_size;
            int burst_item = 0;
            int start_lane_idx = 0;

            // synchroniation variables for allow_outstanding_transactions == 0
            bit addr_handshake_completed [] = new[num_bursts];
            bit data_completed [] = new[num_bursts];

            bit early_rlast = 0;
            bit missing_rlast = 0;

            logic [DATA_WIDTH-1:0] data_axi_recv_raw;
            logic [DATA_WIDTH-1:0] data_axi_recv_masked_strb;
            time time_start;

            // ensure zero-initialization
            for (int i=0; i<num_bursts; i++) begin
                addr_handshake_completed[i] = 0;
                data_completed[i] = 0;
            end

            ats.zero();
            
            if (wait_cycle) @(posedge if_axi.cb);
            time_start = $time;

            if (`VERBOSITY >= VERBOSITY_OPERATION)
                $display("[%0t] **** AXI READ BURST OPERATION ****", $time);
//             if (`VERBOSITY >= VERBOSITY_PROTOCOL)
//                 $display("burst length: %0d - burst size: %0d (DATA_WIDTH: %0d)",
//                     burst_len, int_burst_size, DATA_WIDTH);

            fork

            // ADDRESS HANDSHAKES
            begin
                if_axi.cb.arvalid <= 1;
                for (int transaction=0; transaction<num_bursts; transaction++) begin
                    burst_len_addr = $size(data[transaction]);
                    int_burst_size = $size(data[transaction][0])/8;
                    // TODO: AXI_VERSION dependent
                    assert (int_burst_size inside {1, 2, 4, 8, 16, 32, 64, 128});
                    assert (int_burst_size <= DATA_WIDTH);

                    if_axi.cb.arlen <= burst_len_addr-1;
                    if_axi.cb.arsize <= $clog2(int_burst_size);
                    if_axi.cb.araddr <= address;
                    if_axi.cb.arvalid <= 1;

                    @(posedge if_axi.cb);
                    wait(if_axi.cb.arready);

                    addr_handshake_completed[transaction] = 1;

                    if (~allow_outstanding_transactions) begin
                        if_axi.cb.arvalid <= 0;
                        wait(data_completed[transaction]);
                    end

                    address += burst_len_addr * int_burst_size;

                end
                if_axi.cb.arvalid <= 0;
            end

            // DATA TRANSMISSIONS
            begin: fork_data
                for (int transaction=0; transaction<num_bursts; transaction++)
                begin: transactions
                    if (wait_address_handshake) wait(addr_handshake_completed[transaction]);
                    if_axi.cb.rready <= 1;

                    start_lane_idx = 0;
                    burst_len_data = $size(data[transaction]);
                    int_burst_size = $size(data[transaction][0])/8;

                    for (int burst_item=0; burst_item<burst_len_data; burst_item++)
                    begin: current_burst
                        
                        @(posedge if_axi.cb);
                        wait(if_axi.cb.rvalid);

                        // per bit-for loop is necessary because it is assigning 
                        // from unpacked to packed on bit level
                        for (int idx_bit=0; idx_bit<int_burst_size*8; idx_bit++) begin
                            data[transaction][burst_item][idx_bit] =
                                    if_axi.cb.rdata[start_lane_idx*8+idx_bit];
                        end
                        if (`VERBOSITY >= VERBOSITY_DATA) begin
                            $display("[%0t] read data beat %3d: %h",
                                    $time, burst_item, if_axi.cb.rdata);
                        end

                        // TODO: shouldn't that happen at burst/transaction 
                        // level, and not at item level?
                        resp[burst_item] = if_axi.cb.rresp;
                        if (if_axi.cb.rresp != AXI4_RESP_OKAY) begin
                            $warning("[%0t] read transaction %0d signaled non-okay response %0h",
                                    $time, burst_item, if_axi.cb.rresp);
                        end

                        if (if_axi.cb.rlast && burst_item < burst_len_data-1) begin
                            $warning("[%0t] rlast received before last burst len item", $time);
                            early_rlast = 1;
                        end
                        if (burst_item == burst_len_data-1 && ~if_axi.cb.rlast) begin
                            missing_rlast = 1;
                        end

                        if (missing_rlast) begin
                            // error feels more appropriate than a warning -> if 
                            // something is wrong with the read request, the slave 
                            // might now be blocked because it still wants to 
                            // transmit data, but it will just fail at a later point 
                            // in simulation and you have to backtrack that. And by 
                            // protocol specs, rlast is NOT optional, so not setting 
                            // it is an error, not a warning.
                            $error("[%0t] rlast not received at last burst len item", $time);
                        end
                        if (early_rlast) break;

                        if (burst_item == burst_len_data-1) begin
                            if_axi.cb.rready <= 0;
                        end else begin
                            start_lane_idx = (start_lane_idx+int_burst_size) % (DATA_WIDTH/8);
    //                         @(posedge if_axi.cb);
                        end

                    end // current_burst

                    data_completed[transaction] = 1;

                    ats.num_axi_words += burst_len_data;
                    ats.num_axi_bits += burst_len_data * int_burst_size * 8;
                    ats.num_user_bits += burst_len_data * int_burst_size * 8;

                end // transactions
            end // fork_data

            join

            ats.time_total = $time - time_start;
            ats.time_read = $time - time_start;

        endtask // read_bursts

        // READ/WRITE WORDS

        // TODO: do some correctness tracking via resp. Guess the smartest thing 
        // is aborting as soon as a resp is not OKAY (or maybe EXCLUSIVE OKAY) 
        // and returning that resp. Caller can check the resp, and if it's fine, 
        // you know that the data is valid.
        task write_words(
            input logic [ADDR_WIDTH-1:0]    base_address,
            input cls_test_data             data,
            input cls_axi_transaction_stats ats
        );

            const int                       allow_outstanding_transactions = 1;
            const int                       wait_address_handshake = 0;
            const int                       wait_cycle = 0;

            const int                       num_burst_items = data.get_len();
            const int                       data_bitwidth = data.get_size();
            const int                       int_burst_size =
                                                int_burst_size_from_bitwidth(data_bitwidth);

            int                             burst_len;
            int                             num_bursts;
            logic   [1:0]                   resp [];

            logic                           axi_data [][][];

            // protocol specification
            assert (int_burst_size inside {1, 2, 4, 8, 16, 32, 64, 128});
            assert (int_burst_size <= DATA_WIDTH);

            num_bursts = $ceil(real'(num_burst_items)/MAX_BURST_LEN);

            axi_data = new[num_bursts];

            // all but the last burst maximum length, last burst set up to match 
            // the total number of requested burst elements
            for (int i=0; i<num_bursts; i++) begin
                if (i < (num_bursts-1)) begin
                    axi_data[i] = new[MAX_BURST_LEN];
                end else begin
                    // if num_burst_items is a multiple of MAX_BURST_LEN, just 
                // taking modulo without checking would yield 0 for the last 
                // burst length
                    if (num_burst_items % MAX_BURST_LEN == 0)
                        axi_data[i] = new[MAX_BURST_LEN];
                    else
                        axi_data[i] = new[num_burst_items % MAX_BURST_LEN];
                end
            end

            for (int transaction=0; transaction<num_bursts; transaction++) begin
                burst_len = $size(axi_data[transaction]);
                for (int burst_item=0; burst_item<burst_len; burst_item++) begin
                    axi_data[transaction][burst_item] = new[data_bitwidth];
                    for (int data_bit=0; data_bit<data_bitwidth; data_bit++) begin
                        axi_data[transaction][burst_item][data_bit] =
                                data.data[(transaction*MAX_BURST_LEN)+burst_item][data_bit];
                    end 
                end
            end

            @(posedge if_axi.cb);

            write_bursts(base_address, axi_data, resp, ats,
                    allow_outstanding_transactions, wait_cycle);

            ats.num_user_bits = data.get_len() * data.get_size();

            if (`VERBOSITY >= VERBOSITY_DATA) begin
                data.print256();
            end

        endtask // write_words

        /*
        * INCR read bursts of 'burst_len' and 'burst_size', starting at 
        * 'address'. Sort of a wrapper around the 'read' task if you only need 
        * the transaction stats, but not the data (such that a user does not 
    * have to instantiate and handle cls_test_data objects).
        */
        // TODO: introduce a 'pack' argument: pack as many data objects as 
        // possible into single axi words. Also add a 'pack_exp2_pad' argument: 
        // do packing on power of 2 base, rather than on word base (e.g. align 
        // data objects with power of 2 bits, and pad until the next data object, 
        // instead of data objects right after each other and then pad the 
        // remaining word)
        // TODO: it could be interesting if the task could also read words that 
        // are larger than the axi datawidth/max burst size, by combining 
        // consecutive words.
        task read_words(
            input logic [ADDR_WIDTH-1:0]    base_address,
            input cls_test_data             data,
            input cls_axi_transaction_stats ats
        );

            const int                       allow_outstanding_transactions = 1;
            const int                       wait_address_handshake = 0;
            const int                       wait_cycle = 0;

            const int                       num_burst_items = data.get_len();
            const int                       data_bitwidth = data.get_size();
            const int                       int_burst_size =
                                                int_burst_size_from_bitwidth(data_bitwidth);

            int                             burst_len;
            int                             num_bursts;
            logic   [1:0]                   resp [];

            logic                           axi_data [][][];

            // protocol specification
            assert (int_burst_size inside {1, 2, 4, 8, 16, 32, 64, 128});
            assert (int_burst_size <= DATA_WIDTH);

            num_bursts = $ceil(real'(num_burst_items)/MAX_BURST_LEN);

            axi_data = new[num_bursts];

            // all but the last burst maximum length, last burst set up to match 
            // the total number of requested burst elements
            for (int i=0; i<num_bursts; i++) begin
                if (i < (num_bursts-1)) begin
                    axi_data[i] = new[MAX_BURST_LEN];
                end else begin
                    // if num_burst_items is a multiple of MAX_BURST_LEN, just 
                // taking modulo without checking would yield 0 for the last 
                // burst length
                    if (num_burst_items % MAX_BURST_LEN == 0)
                        axi_data[i] = new[MAX_BURST_LEN];
                    else
                        axi_data[i] = new[num_burst_items % MAX_BURST_LEN];
                end

                for (int j=0; j<$size(axi_data[i]); j++)
                    axi_data[i][j] = new[int_burst_size*8];
            end

            @(posedge if_axi.cb);

            read_bursts(base_address, axi_data, resp, ats,
                    allow_outstanding_transactions, wait_address_handshake, wait_cycle);

            for (int transaction=0; transaction<num_bursts; transaction++) begin
                burst_len = $size(axi_data[transaction]);
                for (int burst_item=0; burst_item<burst_len; burst_item++) begin
                    for (int data_bit=0; data_bit<data_bitwidth; data_bit++) begin
                        data.data[(transaction*MAX_BURST_LEN)+burst_item][data_bit] =
                                axi_data[transaction][burst_item][data_bit];
                    end 
                end
            end

            ats.num_user_bits = data.get_len() * data.get_size();

            if (`VERBOSITY >= VERBOSITY_DATA) begin
                data.print256();
            end
        endtask // read_words

        //----------------------------
        // TEST/BENCHMARKS
        //----------------------------

        /*
        * Write num_write_items randomized items of item_size_bytes using INCR 
        * write bursts, starting at 'base_address'. Wrapper around 'read_words' 
        * for if you only need the transaction stats, but not the data (such 
        * that a user does not have to instantiate and handle cls_test_data 
    * objects).
        */
        task benchmark_write(
            input logic [ADDR_WIDTH-1:0] base_address,
            input int num_write_items,
            input int item_size_bytes,
            input cls_axi_transaction_stats ats
        );
            cls_test_data                   test_data;
            test_data = new(num_write_items, item_size_bytes*8, 1);
            @(posedge if_axi.cb);
            write_words(base_address, test_data, ats);
        endtask // benchmark_write

        /*
        * Read num_read_items randomized items of item_size_bytes using INCR 
        * read bursts, starting at 'base_address'. Wrapper around 'read_words' 
        * for if you only need the transaction stats, but not the data (such 
        * that a user does not have to instantiate and handle cls_test_data 
    * objects).
        */
        task benchmark_read(
            input logic [ADDR_WIDTH-1:0] base_address,
            input int num_read_items,
            input int item_size_bytes,
            input cls_axi_transaction_stats ats
        );
            cls_test_data                   test_data;
            test_data = new(num_read_items, item_size_bytes*8);
            @(posedge if_axi.cb);
            read_words(base_address, test_data, ats);
        endtask // benchmark_read

        /*
        */
        task test_rand_write_read(
            input logic [ADDR_WIDTH-1:0] address,
            input int num_items,
            input int item_size_bytes
        );

            string test_name = "rand write-read";
            string test_desc = "Randomized INCR burst write/read-back";

            cls_test_data data_write;
            cls_test_data data_read;
            cls_axi_transaction_stats ats;

            logic [1:0] write_resp;
            logic [1:0] read_resp [];

            // why packed (static) and not dynamic array?
            // practically, data_correct needs to burst_len elements -> one-hot 
            // data correctness indicator. But by protocol spec max burst length 
            // is 256, and with a packed array it's way easier to check for any 
            // 1 -> overall transfer correct or not.
            bit [255:0] data_correct = '1;
            bit success;

            print_test_start(test_name, test_desc);

            // TODO: create two temporary ats and combine them for total time
            data_write = new(num_items, item_size_bytes*8, 1);
            data_read = new(num_items, item_size_bytes*8, 0);
            ats = new();
            ats.zero();

            write_words(address, data_write, ats);
            // TODO: check if you need a wait cycle in the reading part 
            // (although, if you're not benchmarking, but just checking for data 
            // integrity, doesn't matter)
            read_words(address, data_read, ats);

            // COMPARE WRITE AND READ DATA
            foreach (data_read.data[i]) begin
                if (data_read.data[i] != data_write.data[i]) begin
                    data_correct[i] = 0;
                end else begin
                    data_correct[i] = 1;
                end
            end

            // TODO: make that verbose
            // PRINT WRITE AND READ DATA
            $display("\n---- write data ----");
            data_write.print256();
            $display("---- read data ----");
            data_read.print256();

            // DETERMINE SUCCESS
            // separately check for every possible non-success condition (write 
            // and read data not equal, any write or read response not OKAY); 
            // any failure deasserts success
            success = 1;
            if ( ~(&data_correct) ) begin
                $display("FAILURE: write data != read data");
                success = 0;
            end
            if (write_resp != AXI4_RESP_OKAY) begin
                $display("FAILURE: write response other than OKAY");
                success = 0;
            end
            // TODO: process read responses
//             if (read_resp != AXI4_RESP_OKAY) begin
//                 $display("FAILURE: write data != read data");
//                 success = 0;
//             end

            print_test_result(test_name, success);
            $display("");

        endtask // test_rand_write_read

    endclass // cls_axi_traffic_gen_sim

endpackage // axi_sim_pkg
