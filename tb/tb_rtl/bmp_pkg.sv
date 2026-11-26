//==============================================================================
// bmp_pkg: BMP image class for image simulation, 8-bit (palette) and 24-bit BI_RGB files.
// Pixels are kept top-down, left to right, as B G R bytes, whatever the row order in the file.
//==============================================================================
package bmp_pkg;

    //axis_img_save bookkeeping: the testbench stops when save_done == save_num
    int save_num  = 0;//axis_img_save instances
    int save_done = 0;//instances that have saved their FRAME_NUM frames

    class bmp_image;
        int           width   ;//unit: pixels
        int           height  ;//unit: lines
        int           bpp     ;//bits per pixel of the file: 8 or 24
        bit           is_gray ;//every pixel has B = G = R
        string        path    ;
        byte unsigned pix[]   ;//(y*width + x)*3 + ch, ch 0:B 1:G 2:R

        function new(int w = 0, int h = 0, int bits = 24);
            width   = w;
            height  = h;
            bpp     = bits;
            is_gray = (bits == 8);
            pix     = new[w*h*3];
        endfunction

        function byte unsigned get(int x, int y, int ch);
            return pix[(y*width + x)*3 + ch];
        endfunction

        function void set(int x, int y, byte unsigned b, byte unsigned g, byte unsigned r);
            pix[(y*width + x)*3 + 0] = b;
            pix[(y*width + x)*3 + 1] = g;
            pix[(y*width + x)*3 + 2] = r;
        endfunction

        //8-bit value of a pixel: gray value, or luma of a color pixel
        function byte unsigned gray(int x, int y);
            return (29*get(x, y, 0) + 150*get(x, y, 1) + 77*get(x, y, 2)) >> 8;
        endfunction

        //returns 0 when the file was read; header fields decide size, row order, padding and palette
        function int read(string file);
            byte unsigned f[$];
            byte unsigned pal[$];
            int           fd, c, off, dib, h_raw, planes, comp, clr_num, stride, row_off, idx;
            bit           top_down;
            path = file;
            fd   = $fopen(file, "rb");
            if (fd == 0) begin
                $display("ERROR bmp_image: cannot open %s", file);
                return 1;
            end
            c = $fgetc(fd);
            while (c != -1) begin
                f.push_back(c);
                c = $fgetc(fd);
            end
            $fclose(fd);
            if (f.size() < 54 || f[0] != "B" || f[1] != "M") begin
                $display("ERROR bmp_image: %s is not a BMP file", file);
                return 1;
            end
            off     = u32(f, 10);//pixel data offset: header size + palette, not always 54
            dib     = u32(f, 14);//info header size: 40, 108 or 124
            width   = u32(f, 18);
            h_raw   = u32(f, 22);
            planes  = u16(f, 26);
            bpp     = u16(f, 28);
            comp    = u32(f, 30);
            clr_num = u32(f, 46);
            top_down = h_raw < 0;//negative height: first row in the file is the top line
            height   = top_down ? -h_raw : h_raw;
            if (dib < 40 || planes != 1 || comp != 0 || (bpp != 8 && bpp != 24) || width <= 0 || height <= 0) begin
                $display("ERROR bmp_image: %s: unsupported header (info %0d, planes %0d, compression %0d, %0d-bit, %0dx%0d)",
                         file, dib, planes, comp, bpp, width, h_raw);
                return 1;
            end
            //8-bit: palette of B G R 0 entries right after the info header
            if (bpp == 8) begin
                if (clr_num == 0) clr_num = 256;
                for (int i = 0; i < clr_num*4; i++) pal.push_back(f[14 + dib + i]);
            end
            stride = (width*bpp + 31) / 32 * 4;//every row is padded to 4 bytes
            if (f.size() < off + stride*height) begin
                $display("ERROR bmp_image: %s is shorter than its header says", file);
                return 1;
            end
            pix     = new[width*height*3];
            is_gray = 1;
            for (int r = 0; r < height; r++) begin
                int y = top_down ? r : height - 1 - r;//bottom-up file: first row is the bottom line
                row_off = off + r*stride;
                for (int x = 0; x < width; x++) begin
                    if (bpp == 24)
                        set(x, y, f[row_off + x*3], f[row_off + x*3 + 1], f[row_off + x*3 + 2]);
                    else begin
                        idx = f[row_off + x];
                        if (idx >= clr_num) begin
                            $display("ERROR bmp_image: %s: palette index %0d out of range", file, idx);
                            return 1;
                        end
                        set(x, y, pal[idx*4], pal[idx*4 + 1], pal[idx*4 + 2]);
                    end
                    if (get(x, y, 0) != get(x, y, 1) || get(x, y, 1) != get(x, y, 2)) is_gray = 0;
                end
            end
            $display("bmp_image: read %s: %0dx%0d %0d-bit %s, %s", file, width, height, bpp,
                     top_down ? string'("top-down") : string'("bottom-up"), is_gray ? string'("gray") : string'("color"));
            return 0;
        endfunction

        //bits 8: gray file with palette (luma of color pixels), 24: color file; rows bottom-up, padded
        function int write(string file, int bits = 0);
            byte unsigned h[$];
            int           fd, stride, off, size;
            if (bits == 0) bits = bpp;
            stride = (width*bits + 31) / 32 * 4;
            off    = 14 + 40 + (bits == 8 ? 1024 : 0);
            size   = off + stride*height;
            fd     = $fopen(file, "wb");
            if (fd == 0) begin
                $display("ERROR bmp_image: cannot create %s", file);
                return 1;
            end
            h.push_back("B"); h.push_back("M");
            put32(h, size); put32(h, 0); put32(h, off);
            put32(h, 40); put32(h, width); put32(h, height); put16(h, 1); put16(h, bits);
            put32(h, 0); put32(h, stride*height); put32(h, 2835); put32(h, 2835);
            put32(h, bits == 8 ? 256 : 0); put32(h, 0);
            if (bits == 8)
                for (int i = 0; i < 256; i++) begin
                    h.push_back(i); h.push_back(i); h.push_back(i); h.push_back(0);
                end
            foreach (h[i]) $fwrite(fd, "%c", h[i]);
            for (int y = height - 1; y >= 0; y--) begin
                for (int x = 0; x < width; x++)
                    if (bits == 8) $fwrite(fd, "%c", gray(x, y));
                    else           $fwrite(fd, "%c%c%c", get(x, y, 0), get(x, y, 1), get(x, y, 2));
                for (int p = width*bits/8; p < stride; p++) $fwrite(fd, "%c", 8'h00);
            end
            $fclose(fd);
            return 0;
        endfunction

        static function int u16(ref byte unsigned f[$], input int o);
            return f[o] | (f[o + 1] << 8);
        endfunction

        static function int u32(ref byte unsigned f[$], input int o);
            return f[o] | (f[o + 1] << 8) | (f[o + 2] << 16) | (f[o + 3] << 24);
        endfunction

        static function void put16(ref byte unsigned h[$], input int v);
            h.push_back(v[7:0]); h.push_back(v[15:8]);
        endfunction

        static function void put32(ref byte unsigned h[$], input int v);
            h.push_back(v[7:0]); h.push_back(v[15:8]); h.push_back(v[23:16]); h.push_back(v[31:24]);
        endfunction
    endclass

    //pixel of an image as stream data: CH = 3 packs {R, G, B} (B in the low bits), CH = 1 is the gray value;
    //every 8-bit value is scaled to PIX bits
    class pix_pack #(int CH = 3, int PIX = 8);
        static function logic [CH*PIX-1:0] get(bmp_image img, int x, int y);
            logic [CH*PIX-1:0] v;
            for (int c = 0; c < CH; c++)
                v[c*PIX +: PIX] = from8(CH == 1 ? img.gray(x, y) : img.get(x, y, c));
            return v;
        endfunction

        static function logic [PIX-1:0] from8(byte unsigned v);
            return PIX >= 8 ? PIX'(v) << (PIX - 8) : PIX'(v >> (8 - PIX));
        endfunction

        static function byte unsigned to8(logic [PIX-1:0] v);
            return PIX >= 8 ? 8'(v >> (PIX - 8)) : 8'(v << (8 - PIX));
        endfunction
    endclass

endpackage
