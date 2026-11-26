`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////
// Company               :
// Engineer              :
// Function              :       image simulation template, here with matrix_3x3_gen as the DUT.
//                               Reads one BMP file (8-bit gray or 24-bit color, size from the file header),
//                               sends it FRAME_NUM times, saves every output frame as a BMP file and stops
//                               by itself when every axis_img_save has saved its frames.
//                               Frames 0 .. CONT_FRAME-1: tvalid and tready continuous, later frames: both random.
//                               Another module: change only the DUT block (signals, instance, output select).
//                               Everything is set in this file (parameters, DUT block), the scripts stay unchanged.
//                               Optional plusargs override IMG_FILE / output folder: +IMG=<BMP file> +OUT_DIR=<folder>
// Creat Date            :       2026/11/20
// Module Name           :       tb_top
// Tool Versions         :       questa 2024.1
// Description           :       image testbench of matrix_3x3_gen
// Vresion 1.0           :       File Created

//-------------------- Modification History -----------------------------------
//2026/11/20           v1.0     :     File Created

module tb_top #(
    parameter IMG_FILE              = "../pic/scene_640x480.bmp",//input image, path from the scripts folder
    parameter PIXEL_TAP_NUM         = 4   ,//pixels per beat, image width must be a multiple of it
    parameter CHANNEL_NUM           = 3   ,//3: {R, G, B} per pixel, 1: gray (color files as luma)
    parameter CHANNEL_WIDTH         = 8   ,//bits per channel
    parameter PIXEL_AXIS_USER_WIDTH = 4   ,//0:SOF 1:SOL 2:EOL 3:EOF
    parameter SRC_SEL               = 0   ,//0: image pixels, 1: counter, pixel x in the line
    parameter FRAME_NUM             = 3   ,//frames sent, every axis_img_save waits for this many frames
    parameter CONT_FRAME            = 1   ,//frames before it: tvalid / tready continuous, from it on: random
    parameter LINE_GAP              = 16  ,//unit: clocks between two lines
    parameter FRAME_GAP             = 64   //unit: clocks after the last line of a frame
);

    import bmp_pkg::*;

    localparam PIXEL_WIDTH = CHANNEL_NUM*CHANNEL_WIDTH;           //bits per pixel

    // clock and reset
    logic                                            pixel_clk       = 0  ;
    logic                                            pixel_rst_n     = 0  ;

    // image and configuration
    string                                           img_file        = IMG_FILE;
    string                                           out_dir         = "../pic/out";
    bmp_image                                        img             = new();
    logic [15:0]                                     img_width       = 0  ;//unit: pixels
    logic [15:0]                                     img_height      = 0  ;//unit: lines
    bit                                              test_complete   = 0  ;

    // source -> DUT
    logic                                            src_axis_tvalid      ;
    logic                                            src_axis_tready      ;
    logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0]       src_axis_tdata       ;
    logic [PIXEL_AXIS_USER_WIDTH-1:0]                src_axis_tuser       ;

    always #5 pixel_clk = ~pixel_clk;                             //100 MHz

    //--------------------------------------------------------------------------
    // source
    //--------------------------------------------------------------------------
    axis_img_source #(
        .PIXEL_WIDTH           (PIXEL_WIDTH          ),
        .PIXEL_TAP_NUM         (PIXEL_TAP_NUM        ),
        .PIXEL_AXIS_USER_WIDTH (PIXEL_AXIS_USER_WIDTH),
        .CHANNEL_NUM           (CHANNEL_NUM          ),
        .SRC_SEL               (SRC_SEL              ) //0: image pixels, 1: counter
    ) u_img_source (
        .i_pixel_clk           (pixel_clk            ),
        .o_m_axis_tvalid       (src_axis_tvalid      ),
        .i_m_axis_tready       (src_axis_tready      ),
        .o_m_axis_tdata        (src_axis_tdata       ),
        .o_m_axis_tuser        (src_axis_tuser       )
    );

    //--------------------------------------------------------------------------
    // DUT: change this block for another module
    //--------------------------------------------------------------------------
    // DUT output
    logic [PIXEL_TAP_NUM-1:0][8:0][PIXEL_WIDTH-1:0]  m_matrix_3x3_tdata   ;//0 1 2 / 3 4 5 / 6 7 8, 4 = center

    // DUT output -> axis_img_save
    logic                                            dut_axis_tvalid      ;
    logic                                            dut_axis_tready = 0  ;
    logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0]       dut_axis_tdata       ;//pixels that are saved
    logic [PIXEL_AXIS_USER_WIDTH-1:0]                dut_axis_tuser       ;

    matrix_3x3_gen #(
        .PIXEL_WIDTH           (PIXEL_WIDTH          ),
        .PIXEL_TAP_NUM         (PIXEL_TAP_NUM        ),
        .PIXEL_AXIS_USER_WIDTH (PIXEL_AXIS_USER_WIDTH),
        .PIXEL_LINE_WIDTH_MAX  (2048                 ) //unit: pixels, line buffer depth
    ) u_matrix_3x3_gen (
        .i_pixel_clk           (pixel_clk            ),
        .i_pixel_rst_n         (pixel_rst_n          ),
        .i_x_width             (img_width            ),
        .i_y_height            (img_height           ),
        .i_s_axis_tvalid       (src_axis_tvalid      ),
        .o_s_axis_tready       (src_axis_tready      ),
        .i_s_axis_tdata        (src_axis_tdata       ),
        .i_s_axis_tuser        (src_axis_tuser       ),
        .o_m_axis_tvalid       (dut_axis_tvalid      ),
        .i_m_axis_tready       (dut_axis_tready      ),
        .o_m_axis_tdata        (m_matrix_3x3_tdata   ),
        .o_m_axis_tuser        (dut_axis_tuser       )
    );

    always_comb begin
        for(int i=0;i<PIXEL_TAP_NUM;i++)
            dut_axis_tdata[i] = m_matrix_3x3_tdata[i][4];         //window center
    end

    //--------------------------------------------------------------------------
    // tready of the DUT output: continuous for the first CONT_FRAME frames, then random
    //--------------------------------------------------------------------------
    always @ (posedge pixel_clk) begin
        dut_axis_tready <= (u_img_save.frames < CONT_FRAME) ? 1'b1 : 1'($urandom);
    end

    //--------------------------------------------------------------------------
    // output images; a stream inside the DUT is saved the same way: one more axis_img_save
    // connected by hierarchical names (u_matrix_3x3_gen.<signal>), save_prefix set in the initial block
    //--------------------------------------------------------------------------
    axis_img_save #(
        .PIXEL_WIDTH           (PIXEL_WIDTH          ),
        .PIXEL_TAP_NUM         (PIXEL_TAP_NUM        ),
        .PIXEL_AXIS_USER_WIDTH (PIXEL_AXIS_USER_WIDTH),
        .CHANNEL_NUM           (CHANNEL_NUM          ),
        .FRAME_NUM             (FRAME_NUM            )
    ) u_img_save (
        .i_pixel_clk           (pixel_clk            ),
        .i_pixel_rst_n         (pixel_rst_n          ),
        .i_s_axis_tvalid       (dut_axis_tvalid      ),
        .i_s_axis_tready       (dut_axis_tready      ),
        .i_s_axis_tdata        (dut_axis_tdata       ),
        .i_s_axis_tuser        (dut_axis_tuser       )
    );

    //example of one more output point: the center line of the window inside matrix_3x3_gen,
    //valid / ready / data / user must be the same stage; also uncomment its save_prefix line below
    //axis_img_save #(
    //    .PIXEL_WIDTH           (PIXEL_WIDTH          ),
    //    .PIXEL_TAP_NUM         (PIXEL_TAP_NUM        ),
    //    .PIXEL_AXIS_USER_WIDTH (PIXEL_AXIS_USER_WIDTH),
    //    .CHANNEL_NUM           (CHANNEL_NUM          ),
    //    .FRAME_NUM             (FRAME_NUM            )
    //) u_img_save_center (
    //    .i_pixel_clk           (pixel_clk                          ),
    //    .i_pixel_rst_n         (pixel_rst_n                        ),
    //    .i_s_axis_tvalid       (u_matrix_3x3_gen.matrix_3x3_tvalid ),
    //    .i_s_axis_tready       (u_matrix_3x3_gen.i_m_axis_tready   ),
    //    .i_s_axis_tdata        (u_matrix_3x3_gen.cur_line1_tdata   ),
    //    .i_s_axis_tuser        (u_matrix_3x3_gen.cur_tuser         )
    //);

    //--------------------------------------------------------------------------
    // read the image, send FRAME_NUM frames, stop when every axis_img_save is done
    //--------------------------------------------------------------------------
    initial begin
        void'($value$plusargs("IMG=%s"    , img_file));
        void'($value$plusargs("OUT_DIR=%s", out_dir ));
        if(img.read(img_file) != 0)
            $fatal(1, "cannot read %s", img_file);
        if(img.width % PIXEL_TAP_NUM != 0)
            $fatal(1, "image width %0d is not a multiple of PIXEL_TAP_NUM %0d", img.width, PIXEL_TAP_NUM);
        u_img_save.save_prefix = {out_dir, "/dut_out"};
        //u_img_save_center.save_prefix = {out_dir, "/center_line"};
        repeat(10) @ (posedge pixel_clk);
        img_width   <= img.width;
        img_height  <= img.height;
        pixel_rst_n <= 1'b1;
        repeat(10) @ (posedge pixel_clk);
        for(int f=0;f<FRAME_NUM;f++)
            u_img_source.send_frame(img, f >= CONT_FRAME, LINE_GAP, FRAME_GAP);
        wait(save_done == save_num);                              //every axis_img_save has saved its frames
        repeat(100) @ (posedge pixel_clk);
        $display("> Simulate Done: %0d frames, %0d saved streams, output in %s", FRAME_NUM, save_num, out_dir);
        test_complete = 1;
        $stop;
    end

    //////////////debug///////////////////

endmodule
