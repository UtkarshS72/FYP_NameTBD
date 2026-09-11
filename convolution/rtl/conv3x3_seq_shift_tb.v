`timescale 1ns / 1ps

module conv3x3_seq_shift_tb();

    reg clk;
    reg rst;
    reg start;
    
    reg [71:0] pixels;
    reg [71:0] kernel;
    
    wire signed [19:0] result;
    wire done;
    
    integer errors;
    integer test_count;
    
    integer i;
    integer seed;
    
    reg [71:0] random_pixels;
    reg [71:0] random_kernel;
    
    localparam EXPECTED_LATENCY = 9;
    
    // instantiate DUT
    
    conv3x3_seq_shift dut(  // only DUT changed, the rest of the testbench is the same
        .clk(clk),
        .rst(rst),
        .start(start),
        .pixels(pixels),
        .kernel(kernel),
        .result(result),
        .done(done)
    );
    
    // 100MHz simulation clk
    always #5 clk = ~clk;
    
    // golden model
    function signed [19:0] golden_conv;
        
        input [71:0] pixels_in;
        input [71:0] kernel_in;
        
        integer i;
        
        reg [7:0] pixel;
        reg signed [7:0] coeff;
        
        reg signed [8:0] pixel_ext;
        reg signed [8:0] coeff_ext;
        
        reg signed [19:0] sum;
        
        begin
            sum = 0;
            
            for(i = 0; i < 9; i = i + 1) begin
                
                pixel = pixels_in[i*8 +:8];
                coeff = kernel_in[i*8 +:8];
                
                pixel_ext = {1'b0, pixel};
                coeff_ext = {coeff[7], coeff};

                sum = sum + (pixel_ext * coeff_ext);
            end
            golden_conv = sum;
        end
    endfunction
    
    // run_task
    
    task run_test;
    
        input [71:0] pixels_in;
        input [71:0] kernel_in;
        
        reg signed [19:0] expected;
        
        integer cycles_waited;
        
        begin
        
            test_count = test_count + 1;
            
            expected = golden_conv(pixels_in, kernel_in);
            
            // apply inputs
            @(negedge clk);
            
            pixels = pixels_in;
            kernel = kernel_in;
            start = 1;
            
            // DUT accepts start here
            @(posedge clk);
            #1;
            
            // remove start 
            @(negedge clk);
            start = 0;
            
            cycles_waited = 0;
            
            while((done!==1'b1)&&(cycles_waited < 15)) begin
                
                @(posedge clk);
                #1;
                
                cycles_waited = cycles_waited + 1;
            end
            
            // timeout check
            if(done!==1) begin
            
                $display("FAIL test %0d: timeout waiting for done", 
                test_count);
                
                errors = errors + 1;
                
            end
            else begin

            // Result check
                if (result !== expected) begin
                    $display(
                        "FAIL test %0d: pixels=%018h kernel=%018h expected=%0d got=%0d",
                        test_count,
                        pixels_in,
                        kernel_in,
                        expected,
                        result
                    );
                
                    errors = errors + 1;
                end
                if (cycles_waited !== EXPECTED_LATENCY) begin
                    $display(
                        "FAIL test %0d: expected latency=%0d cycles, got=%0d",
                        test_count,
                        EXPECTED_LATENCY,
                        cycles_waited
                    );
                
                    errors = errors + 1;
                end   
                @(posedge clk);
                #1;
                if(done!==1'b0) begin
                    $display(
                        "FAIL test %0d: done failed to return to zero",
                        test_count
                    );
                    
                    errors = errors + 1;
                end
            end           
        end
     endtask   
     
     task test_start_while_active;

        reg [71:0] pixels_a;
        reg [71:0] kernel_a;
    
        reg [71:0] pixels_b;
        reg [71:0] kernel_b;
    
        reg signed [19:0] expected_a;
    
        integer cycles_waited;
    
        begin
            test_count = test_count + 1;
    
            // Transaction A
            pixels_a = 72'h010101010101010101;
            kernel_a = 72'h010101010101010101;
            // expected A = 9
    
            // Completely different transaction B
            pixels_b = 72'hFFFFFFFFFFFFFFFFFF;
            kernel_b = 72'h010101010101010101;
            // would give 2295 if accepted
    
            expected_a = golden_conv(pixels_a, kernel_a);
    
            // Start A
            @(negedge clk);
            pixels = pixels_a;
            kernel = kernel_a;
            start  = 1;
    
            @(posedge clk);
            #1;
    
            @(negedge clk);
            start = 0;
    
            // Let A process a few elements
            repeat (3) begin
                @(posedge clk);
                #1;
            end
    
            // Try to start B while DUT is still active
            @(negedge clk);
            pixels = pixels_b;
            kernel = kernel_b;
            start  = 1;
    
            @(posedge clk);
            #1;
    
            @(negedge clk);
            start = 0;
    
            // Wait for original transaction to finish
            cycles_waited = 0;
    
            while ((done !== 1'b1) &&
                   (cycles_waited < 15)) begin
                @(posedge clk);
                #1;
                cycles_waited = cycles_waited + 1;
            end
    
            if (done !== 1'b1) begin
                $display(
                    "FAIL test %0d: timeout in start-while-active test",
                    test_count
                );
                errors = errors + 1;
            end
            else if (result !== expected_a) begin
                $display(
                    "FAIL test %0d: active transaction was corrupted; expected=%0d got=%0d",
                    test_count,
                    expected_a,
                    result
                );
                errors = errors + 1;
            end
    
        end
    endtask
    
    task test_reset_mid_operation;

        begin
            test_count = test_count + 1;
    
            // Start a nontrivial convolution
            @(negedge clk);
            pixels = 72'hFFFFFFFFFFFFFFFFFF;
            kernel = 72'h7F7F7F7F7F7F7F7F7F;
            start  = 1;
    
            @(posedge clk);
            #1;
    
            @(negedge clk);
            start = 0;
    
            // Allow a few MAC cycles
            repeat (3) @(posedge clk);
    
            // Assert asynchronous reset between clocks
            #2;
            rst = 0;
    
            #1;
    
            if (done !== 1'b0) begin
                $display(
                    "FAIL test %0d: done not cleared by reset",
                    test_count
                );
                errors = errors + 1;
            end
    
            if (result !== 20'sd0) begin
                $display(
                    "FAIL test %0d: result not cleared by reset",
                    test_count
                );
                errors = errors + 1;
            end
    
            // Release reset safely
            @(negedge clk);
            rst = 1;
    
        end
    endtask
    // run test
    
    initial begin

        clk        = 0;
        rst        = 0;
        start      = 0;
        pixels     = 0;
        kernel     = 0;
        errors     = 0;
        test_count = 0;

        // reset is active-low
        repeat (2) @(posedge clk);

        @(negedge clk);
        rst = 1;

        // tests go here

        run_test(
            72'h000000000000000000, // all zero
            72'h000000000000000000
        );
        
        run_test(
            72'h010101010101010101, // 1*1, added 9 times
            72'h010101010101010101
        );
        
        run_test(
            72'h010101010101010101, // 1*(-1), added 9 times
            72'hFFFFFFFFFFFFFFFFFF
        );

        run_test(
            72'hFFFFFFFFFFFFFFFFFF, // max positive
            72'h7F7F7F7F7F7F7F7F7F
        );
        
        run_test(
            72'hFFFFFFFFFFFFFFFFFF, // max negative
            72'h808080808080808080
        );
        
        run_test(
            72'h000000000000000001, // pixel = 1
            72'h00000000000000007F  // coeff = +127
        );
        // expected = +127
        
        run_test(
            72'h000000000000000001, // pixel = 1
            72'h000000000000000080  // coeff = -128
        );
        // expected = -128
        
        run_test(
            72'h000000000000000001,
            72'h0000000000000000FF  // coeff = -1
        );
        // expected = -1
        
        run_test(
            72'h0000000000000000FF, // 255
            72'h000000000000000001
        );
        
        run_test(
            72'h0000000000000A0A0A, // cancellation case
            72'h00000000000001807F
        );
        
        run_test(
            72'h090807060504030201,
            72'h0403020100FFFEFDFC
        );
        
        test_start_while_active();
        
        run_test(
            72'h010101010101010101,
            72'h010101010101010101
        );
        
        run_test(
            72'h020202020202020202,
            72'h010101010101010101
        );
        
        test_reset_mid_operation();

        run_test(
            72'h010101010101010101,
            72'h010101010101010101
        );
        
        // Randomized tests
        seed = 12345;
        
        $display("Starting randomized tests with seed = %0d", seed);
        
        for (i = 0; i < 1000; i = i + 1) begin
        
            random_pixels = {
                $random(seed),
                $random(seed),
                $random(seed)
            };
        
            random_kernel = {
                $random(seed),
                $random(seed),
                $random(seed)
            };
        
            run_test(
                random_pixels,
                random_kernel
            );
        
        end 

        if (errors == 0)
            $display("ALL %0d TESTS PASSED", test_count);
        else
            $display(
                "%0d ERROR(S) ACROSS %0d TEST(S)",
                errors, test_count
            );

        $finish;
    end

endmodule
