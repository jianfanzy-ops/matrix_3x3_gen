`timescale 1ns/1ps
////////////////////////////////////////////////////////////////////////////
// Company               :
// Engineer              :
// Function              :       watches an AXI4-Stream and saves every frame as a BMP file, nothing is driven,
//                               so it can tap the DUT output or any stream inside the DUT.
//                               The size comes from tuser (pixels up to EOL, lines up to EOF), it may differ
//                               from the input size. CHANNEL_NUM 1 saves 8-bit gray files, 3 saves 24-bit files.
//                               Every instance counts itself in bmp_pkg::save_num and adds to bmp_pkg::save_done
//                               after FRAME_NUM frames; the testbench stops when the two are equal.
// Creat Date            :       2026/11/20
// Module Name           :       axis_img_save
// Tool Versions         :       questa 2024.1
// Description           :       image saver for simulation, axi_stream interface
// Vresion 1.0           :       File Created

//-------------------- Modification History -----------------------------------
//2026/11/20           v1.0     :     File Created

module axis_img_save #(
    parameter PIXEL_WIDTH           = 24  ,//bits per pixel, CHANNEL_NUM channels
    parameter PIXEL_TAP_NUM         = 4   ,//pixels per beat
    parameter PIXEL_AXIS_USER_WIDTH = 4   ,//0:SOF 1:SOL 2:EOL 3:EOF
    parameter CHANNEL_NUM           = 3   ,//3: {R, G, B} per pixel, 1: gray
    parameter FRAME_NUM             = 1    //frames to save before the simulation may stop
)(
    input  logic                                            i_pixel_clk         ,
    input  logic                                            i_pixel_rst_n       ,//active-low
    // stream that is saved, all inputs
    input  logic                                            i_s_axis_tvalid     ,
    input  logic                                            i_s_axis_tready     ,//tready of that stream
    input  logic [PIXEL_TAP_NUM-1:0][PIXEL_WIDTH-1:0]       i_s_axis_tdata      ,
    input  logic [PIXEL_AXIS_USER_WIDTH-1:0]                i_s_axis_tuser
);

    `include "define_isp.sv"
    import bmp_pkg::*;

    localparam CHANNEL_WIDTH = PIXEL_WIDTH/CHANNEL_NUM;           //bits per channel
    localparam FILE_BITS     = (CHANNEL_NUM == 1) ? 8 : 24;       //bits per pixel of the saved file

    // handshake
    logic                                            s_axis_hs            ;

    // frame being received
    int                                              line_pixel_cnt  = 0  ;//unit: pixels, current line
    int                                              line_width      = 0  ;//unit: pixels, first line of the frame
    int                                              frame_line_cnt  = 0  ;//unit: lines
    byte unsigned                                    frame_pix[$]         ;//B G R of every pixel, in order

    // set by the testbench, results
    string                                           save_prefix     = "" ;//frame n is saved as <save_prefix>_f<n>.bmp
    int                                              frames          = 0  ;//frames saved

    initial save_num++;                                           //one more axis_img_save instance

    //--------------------------------------------------------------------------
    // save one frame, called on EOF
    //--------------------------------------------------------------------------
    task automatic end_frame();
        bmp_image   img;
        string      file;
        img  = new(line_width, frame_line_cnt, FILE_BITS);
        file = $sformatf("%s_f%0d.bmp", save_prefix, frames);
        for(int i=0;i<img.pix.size() && i<frame_pix.size();i++)
            img.pix[i] = frame_pix[i];
        void'(img.write(file));
        $display("axis_img_save: frame %0d %0dx%0d -> %s", frames, line_width, frame_line_cnt, file);
        if(frames + 1 == FRAME_NUM)
            save_done++;                                          //this instance has saved its frames
        frames <= frames + 1;
    endtask

    //--------------------------------------------------------------------------
    // collect the pixels of a frame, SOF starts a new frame
    //--------------------------------------------------------------------------
    assign s_axis_hs = i_s_axis_tvalid & i_s_axis_tready & i_pixel_rst_n;

    always @ (posedge i_pixel_clk) begin
        if(~i_pixel_rst_n | (s_axis_hs & `i_sof)) begin
            line_pixel_cnt = 0;
            frame_line_cnt = 0;
            frame_pix.delete();
        end
        if(s_axis_hs) begin
            for(int i=0;i<PIXEL_TAP_NUM;i++)
                for(int c=0;c<3;c++)
                    frame_pix.push_back(pix_pack#(CHANNEL_NUM, CHANNEL_WIDTH)::to8(i_s_axis_tdata[i][(CHANNEL_NUM == 1 ? 0 : c)*CHANNEL_WIDTH +: CHANNEL_WIDTH]));
            line_pixel_cnt += PIXEL_TAP_NUM;
            if(`i_eol) begin
                if(frame_line_cnt == 0)
                    line_width = line_pixel_cnt;
                frame_line_cnt++;
                line_pixel_cnt = 0;
                if(`i_eof)
                    end_frame();
            end
        end
    end

    //////////////debug///////////////////

endmodule
