package hardcoreConfig;
	typedef enum logic [1:0] {CM_NOT_PRESENT = 2'b00, CM_READ_ONLY = 2'b01, CM_WRITE_ONLY = 2'b10, CM_BIDIRECTIONAL = 2'b11} channelMode_t;
	typedef enum logic [2:0] {CT_GENERIC, CT_DRAM, CT_OPTICAL, CT_SSD, CT_ICAP, CT_INTERFPGA, CT_LOOPBACK, CT_USER} channelType_t;
	
	class channelInfoParser #(int unsigned CHANNELS = 4);
		//According to : https://forums.xilinx.com/xlnx/board/crawl_message?board.id=SYNTHBD&message.id=14734
		//We have to import and not use module names inside the function
		
		/*
		 * Return the number of channels operating in the <channelmode> mode.
		 * 
		 * channels      channel configuration vector
		 * channelmode   mode that we care for
		 * 
		 * @return       # of channels configured in channelmode 
		 */
		static function int channelModeCount(channelMode_t [0:CHANNELS-1] channels, channelMode_t channelmode);
		begin
			automatic int count = 0;
			
			for(int i=0; i<CHANNELS; ++i) begin
				if(channels[i] == channelmode) begin
					count++;
				end
			end
			
			return count;
		end
		endfunction
		
		/*
		 * Returns the channel index for the i-th channel operating in the specified mode.
		 * 
		 * 
		 * channels      channel configuration vector
		 * channelmode   mode that we care for
		 * 
		 * @return       index of the i-th channel configured in channelmode.
		 */
		static function int channelIDForMode(int ID, channelMode_t [0:CHANNELS-1] channels, channelMode_t channelmode);
		begin
			automatic int count = 0;
			automatic int channelId = -1;
			
			for(channelId = 0; channelId<CHANNELS; ++channelId) begin
				if(channels[channelId] == channelmode) begin
					if(count == ID) begin
						break;
					end
					
					count++;
				end
			end
			
			return channelId;
		end
		endfunction		
	endclass
endpackage