`timescale 1ns / 1ps

module vmul(
    input wire clk,
    input wire rst,
    input wire [31:0] din1,
    input wire [31:0] din2,
    input wire din_rdy,
    output wire [31:0] dout,
    output wire dout_rdy
    );

reg [4:0] STATE,NEXT_STATE;
parameter Reset_ST=0, 
                ST_WAIT_DIN=1,
                ST_DIV_DIN=2,
                ST_CHECK_DIN=3,
                ST_CHECK_DEN=4,
                ST_MUL=5,
                ST_DIV_PR=6,
                ST_NORM_Z=7,
                ST_SHIFT_ZDX=8,
                ST_SHIFT_ZSX=9,
                ST_ROUND_Z=10,
                ST_CHECK_Z=11,
                ST_NAN=12,
                ST_INF=13,
                ST_ZERO=14,
                ST_OUT_Z=15,
                ST_OUT_ZDEN=16;

reg [31:0] z;
reg [23:0] x_m, y_m, z_m;
reg [9:0] x_e, y_e, z_e;
reg x_s,y_s,z_s;
reg z_rdy;

reg [47:0] prod;//store x_m*y_m
reg guard //most signif round bit
    ,round//next to guard
    ,stky;//or with all remaning bits

assign dout = z;
assign dout_rdy = z_rdy;


//FSM
always@(STATE,din_rdy,din1,din2)
begin
case(STATE)
    Reset_ST:begin
        NEXT_STATE <= ST_WAIT_DIN;
    end
    ST_WAIT_DIN:begin
        if (din_rdy == 1'b1) 
            NEXT_STATE <= ST_DIV_DIN;
        else
            NEXT_STATE <= ST_WAIT_DIN;
    end
    
    ST_DIV_DIN:begin
        NEXT_STATE <= ST_CHECK_DIN;
    end
    
    ST_CHECK_DIN:begin
        //x or y == nan
        if((x_e == 10'd128 && x_m != 24'd0) || (y_e == 10'd128 && y_m != 24'd0))begin
            NEXT_STATE <= ST_NAN;
        //x == inf
        end else if(x_e == 10'd128)begin
            //y == 0
            if(y_e == -10'd127 && y_m == 24'd0)begin
                NEXT_STATE <= ST_NAN;
            end else begin
                NEXT_STATE <= ST_INF;
            end
        //y == inf
        end else if(y_e == 10'd128)begin
            //x == 0
            if(x_e == -10'd127 && x_m == 24'd0)begin
                NEXT_STATE <= ST_NAN;
            end else begin
                NEXT_STATE <= ST_INF;
            end
        //x or y == 0
        end else if((x_e == -10'd127 && x_m == 24'd0)||(y_e == -10'd127 && y_m == 24'd0))begin
            NEXT_STATE <= ST_ZERO;
        end else begin
            NEXT_STATE <= ST_CHECK_DEN;
        end
    end
    
    ST_CHECK_DEN:begin
        NEXT_STATE <= ST_MUL;
    end
    
    ST_MUL:begin
        NEXT_STATE <= ST_DIV_PR;
    end
    
    ST_DIV_PR:begin
        NEXT_STATE <= ST_NORM_Z;
    end
    
    ST_NORM_Z:begin
        //underflow
        if($signed(z_e) < -150)begin
            NEXT_STATE <= ST_ZERO;
        //denorm
        end else if($signed(z_e) < -126)begin
            NEXT_STATE <= ST_SHIFT_ZDX;
        //overflow
        end else if ((z_m[23]== 1'b1 && $signed(z_e) > 127) || $signed(z_e) > 151) begin
            NEXT_STATE <= ST_INF;
        //normalize
        end else if(z_m[23]== 1'b0 && $signed(z_e) > -126)begin
            NEXT_STATE <= ST_SHIFT_ZSX;
        end else begin
            NEXT_STATE <= ST_ROUND_Z;
        end
    end
    
    ST_SHIFT_ZSX:begin
        NEXT_STATE <= ST_NORM_Z;
    end
    
    ST_SHIFT_ZDX:begin
        NEXT_STATE <= ST_NORM_Z;
    end
    
    ST_ROUND_Z:begin
        NEXT_STATE <= ST_CHECK_Z;
    end
    
    ST_CHECK_Z:begin
        //overflow after round
        if ($signed(z_e) > 127) begin
            NEXT_STATE <= ST_INF;
        //denorm num
        end else if (z_m[23] == 1'b0) begin
            NEXT_STATE <= ST_OUT_ZDEN;
        end else begin
            NEXT_STATE <= ST_OUT_Z;
        end
    end
    
    ST_OUT_Z:begin
        NEXT_STATE <= ST_WAIT_DIN;
    end
    
    ST_OUT_ZDEN:begin
        NEXT_STATE <= ST_WAIT_DIN;
    end
    
    ST_NAN:begin
        NEXT_STATE <= ST_WAIT_DIN;
    end
    
    ST_INF:begin
        NEXT_STATE <= ST_WAIT_DIN;
    end
    
    ST_ZERO:begin
        NEXT_STATE <= ST_WAIT_DIN;
    end
    
    default: begin
        NEXT_STATE <= STATE;
    end
    
    endcase
end

//datapath
always@(posedge clk, posedge rst)
begin
    if (rst == 1'b1) begin
        STATE<=Reset_ST;
    end
    else
    begin 
       STATE <=NEXT_STATE;
       case(NEXT_STATE)
            Reset_ST:begin
                z <= 32'b0;
                x_m <= 24'b0;
                y_m <= 24'b0;
                z_m <= 24'b0;
                x_e <= 10'b0;
                y_e <= 10'b0;
                z_e <= 10'b0;
                x_s <= 1'b0;
                y_s <= 1'b0;
                z_s <= 1'b0;
                z_rdy <= 1'b0;
                prod <= 48'b0;
                guard <= 1'b0;
                round <= 1'b0;
                stky <= 1'b0;
            end
            
            ST_WAIT_DIN:begin
                z_rdy <= 1'b0;
                x_m <= 24'b0;
                y_m <= 24'b0;
                z_m <= 24'b0;
                x_e <= 10'b0;
                y_e <= 10'b0;
                z_e <= 10'b0;
                x_s <= 1'b0;
                y_s <= 1'b0;
                z_s <= 1'b0;
                prod <= 48'b0;
                guard <= 1'b0;
                round <= 1'b0;
                stky <= 1'b0;
            end
            
            ST_DIV_DIN:begin
                //clean old result
                z <= 32'b0;
                z_rdy <= 1'b0;
                //take new input
                x_m <= din1[22 : 0];
                y_m <= din2[22 : 0];
                x_e <= din1[30 : 23] - 127;//elim bias
                y_e <= din2[30 : 23] - 127;//elim bias
                x_s <= din1[31];
                y_s <= din2[31];
            end
            
            ST_CHECK_DIN:begin
                
            end
            
            ST_CHECK_DEN:begin
                //x == denorm -> 01... * 2^-126
                if(x_e == -10'd127 && x_m != 24'd0)begin
                    x_e <= -10'd126;
                end else begin
                    x_m[23] <= 1'b1;
                end
                //y == denorm -> 01... * 2^-126
                if(y_e == -10'd127 && y_m != 24'd0)begin
                    y_e <= -10'd126;
                end else begin
                    y_m[23] <= 1'b1;
                end
            end
            
            ST_MUL:begin
                z_s <= x_s ^ y_s;
                //implicit shift, 1.1* x 1.1* = 11.*
                z_e <= x_e + y_e + 1'b1;
                prod <= x_m * y_m;
            end
            
            ST_DIV_PR:begin
                z_m <= prod[47:24];
                guard <= prod[23];
                round <= prod[22];
                stky <= (prod[21:0] != 0);
            end
            
            ST_NORM_Z:begin
            end
            
            ST_SHIFT_ZSX:begin
                z_e <= z_e - 1;
                z_m <= z_m << 1;
                z_m[0] <= guard;
                guard <= round;
                round <= 0;
            end
            
            ST_SHIFT_ZDX:begin
                z_e <= z_e + 1;
                z_m <= z_m >> 1;
                guard <= z_m[0];
                round <= guard;
                stky <= stky | round;
            end
            
            ST_ROUND_Z:begin
                //GRS
                //0xx do nothing
                //100 round up if the bit before G is 1
                //101,110,111 round up
                if (guard && (round | stky | z_m[0])) begin
                  z_m <= z_m + 1;
                  if (z_m == 24'hffffff) begin
                    z_e <=z_e + 1;
                  end
                end
            end
            
            ST_CHECK_Z:begin
            end
            
            ST_OUT_Z:begin
                z[22 : 0] <= z_m[22:0];
                //add bias exp
                z[30 : 23] <= z_e[7:0]+ 127;
                z[31] <= z_s;
                z_rdy <= 1'b1;
            end
            
            ST_OUT_ZDEN:begin
                z[22 : 0] <= z_m[22:0];
                z[30 : 23] <= 8'd0;
                z[31] <= z_s;
                z_rdy <= 1'b1;
            end
        
            ST_NAN:begin
                z[31] <= 1'b1;
                z[30:23] <= 8'hff;
                z[22:0] <= 23'hffffff;
                z_rdy <= 1'b1;
            end
        
            ST_INF:begin
                z[31] <= z_s;
                z[30:23] <= 8'hff;
                z[22:0] <= 23'd0;
                z_rdy <= 1'b1;
            end
        
            ST_ZERO:begin
                z[31] <= z_s;
                z[30:23] <= 8'd0;
                z[22:0] <= 23'd0;
                z_rdy <= 1'b1;
            end
        
            default: begin
            end
        
        endcase
    end
end

endmodule