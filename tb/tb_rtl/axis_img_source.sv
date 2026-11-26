`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////
// Company               :
// Engineer              :
// Function              :       sends a BMP image as an AXI4-Stream, PIXEL_TAP_NUM pixels per beat.
//                               Pixel i of a beat is pixel x+i of the line (new pixel in the high bits),
//                               tdata / tuser carry garbage while tvalid is low.
//                               The tasks drive with nonblocking assignments on the rising edge.
// Creat Date            :       2026/11/20
// Module Name           :       axis_img_source
// Tool Versions         :       questa 2024.1
// Description           :       image source for simulation, axi_stream interface
// Vresion 1.0           :       File Created

//-------------------- Modification History -----------------------------------
//2026/11/20           v1.0     :     File Created

module axis_img_source #(
    parameter PIXEL_WIDTH           = 24  ,//bits per pixel, CHANNEL_NUM channels
    parameter PIXEL_TAP_NUM         = 4   ,//pixels per beat, image width must be a multiple of it
    parameter PIXEL_AXIS_USER_WIDTH = 4   ,//0:SOF 1:SOL 2:EOL 3:EOF
    parameter CHANNEL_NUM           = 3   ,//3: {R, G, B} per pixel, 1: gray (color files as luma)
    parameter SRC_SEL               = 0    //0: image pixels, 1: counter, pixel x in the line (0, 1, 2 ...)
)(
    input  logic                                            i_pixel_clk         ,
    // output stream
    output logic                                            o_m_axis_tvalid = 0 ,
    input  logic                                            i_m_axis_tready     ,
    output logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0]       o_m_axis_tdata  = 0 ,//new pixel in the high bits
    output logic [PIXEL_AXIS_USER_WIDTH-1:0]                o_m_axis_tuser  = 0
);

    `include "define_isp.sv"
    import bmp_pkg::*;

    localparam CHANNEL_WIDTH = PIXEL_WIDTH/CHANNEL_NUM;//bits per channel

    // results
    int                                              frames          = 0  ;//frames sent

    //--------------------------------------------------------------------------
    // one beat, held until the handshake
    //--------------------------------------------------------------------------
    task automatic beat(
        input logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0]    tdata,
        input logic [PIXEL_AXIS_USER_WIDTH-1:0]             tuser
    );
        o_m_axis_tvalid <= 1'b1;
        o_m_axis_tdata  <= tdata;
        o_m_axis_tuser  <= tuser;
        do @ (posedge i_pixel_clk); while(~i_m_axis_tready);
    endtask

    //--------------------------------------------------------------------------
    // idle clocks: tvalid low, garbage tdata / tuser
    //--------------------------------------------------------------------------
    task automatic idle(input int clocks);
        repeat(clocks) begin
            o_m_axis_tvalid <= 1'b0;
            o_m_axis_tdata  <= {(PIXEL_TAP_NUM*PIXEL_WIDTH+31)/32{$urandom}};
            o_m_axis_tuser  <= PIXEL_AXIS_USER_WIDTH'($urandom);
            @ (posedge i_pixel_clk);
        end
    endtask

    //--------------------------------------------------------------------------
    // one frame; valid_random 0: tvalid high for every beat of a line,
    // 1: 1..3 idle clocks before about half of the beats
    //--------------------------------------------------------------------------
    task automatic send_frame(
        input bmp_image                                     img,
        input bit                                           valid_random = 0,
        input int                                           line_gap     = 16,//unit: clocks
        input int                                           frame_gap    = 64 //unit: clocks
    );
        logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0]   tdata;
        logic [PIXEL_AXIS_USER_WIDTH-1:0]            tuser;
        for(int y=0;y<img.height;y++) begin
            for(int x=0;x<img.width;x+=PIXEL_TAP_NUM) begin
                for(int i=0;i<PIXEL_TAP_NUM;i++)
                    tdata[i] = (SRC_SEL == 1) ? PIXEL_WIDTH'(x + i) : pix_pack#(CHANNEL_NUM, CHANNEL_WIDTH)::get(img, x + i, y);
                tuser       = '0;
                tuser[`SOF] = (y == 0) & (x == 0);
                tuser[`SOL] = (x == 0);
                tuser[`EOL] = (x + PIXEL_TAP_NUM == img.width);
                tuser[`EOF] = (x + PIXEL_TAP_NUM == img.width) & (y == img.height - 1);
                if(valid_random & $urandom_range(1))
                    idle($urandom_range(3, 1));
                beat(tdata, tuser);
            end
            idle(line_gap);
        end
        idle(frame_gap);
        frames++;
    endtask

    //////////////debug///////////////////

endmodule
