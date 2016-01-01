//VIVADO forgets to include our parameter only package, so we force it to
//`include "pcie.sv"
import pcie::*;

package pcieInterfaces;
	parameter BYTEBITS       = 8; //used for the byteenable granularity
	parameter INTERFACEWIDTH = 256;
	parameter INTERFACEBYTES = INTERFACEWIDTH/BYTEBITS;
	parameter DWORDS         = INTERFACEWIDTH/pcie::DWORDBITS;
	parameter PCIE_KEEP_BITS = DWORDS;	
	parameter BYTEENABLEBITS = INTERFACEBYTES; //INTERFACEWIDTH/BYTEBITS;
	parameter TAG_BITS       = 6; //found here since this is a limitation of xilinx's core rather than pcie (whic allows 8 bits)
endpackage

//NOTE: Structs here are defined the 'right way round, since they are connected directly to the xilinx pcie cores outputs'
typedef struct packed {
	logic [31:0] parity;
	logic  [7:0] tph_steeringTag;
	logic  [1:0] tph_type;
	logic        tph_present;
	logic        discontinue;
	logic        startOfPacket;
	logic [31:0] byteEnable;
	logic  [3:0] byteEnable_last;
	logic  [3:0] byteEnable_first;
} pcie_completerRequest_user;

interface pcie_completerRequest;
	logic [pcieInterfaces::INTERFACEWIDTH-1:0] data;                                      // output wire [255 : 0] m_axis_cq_tdata
	pcie_completerRequest_user user;                                   // output wire [84 : 0] m_axis_cq_tuser
	logic         last;                                   // output wire m_axis_cq_tlast
	logic   [pcieInterfaces::PCIE_KEEP_BITS-1:0] keep;                                   // output wire [7 : 0] m_axis_cq_tkeep
	logic         valid;                                   // output wire m_axis_cq_tvalid
	logic         ready;                                   // input wire [21 : 0] m_axis_cq_tready
	
	modport pcieCore(
		output data,
		output user,
		output last,
		output keep,
		output valid,
		input ready
	);

	modport userLogic(
		input data,
		input user,
		input last,
		input keep,
		input valid,
		output ready
	);
	
endinterface

typedef struct packed {
	logic [31:0] parity;
	logic        discontinue;
} pcie_completerCompletion_user;

interface pcie_completerCompletion;
	logic [pcieInterfaces::INTERFACEWIDTH-1:0] data;                                    // input wire [255 : 0] s_axis_cc_tdata
	pcie_completerCompletion_user user;                                    // input wire [32 : 0] s_axis_cc_tuser
	logic         last;                                    // input wire s_axis_cc_tlast
	logic   [pcieInterfaces::PCIE_KEEP_BITS-1:0] keep;                                    // input wire [7 : 0] s_axis_cc_tkeep
	logic         valid;                                    // input wire s_axis_cc_tvalid
	logic   [3:0] ready;                                    // output wire [3 : 0] s_axis_cc_tready
	
	modport pcieCore(
		input data,
		input user,
		input last,
		input keep,
		input valid,
		output ready
	);

	modport userLogic(
		output data,
		output user,
		output last,
		output keep,
		output valid,
		input ready
	);
endinterface

typedef struct packed {
	logic [31:0] parity;
	logic  [3:0] sequenceNumber;
	logic  [7:0] tph_steeringTag;
	logic        tph_indirectTag_enable;
	logic  [1:0] tph_type;
	logic        tph_present;
	logic        discontinue;
	logic  [2:0] offset;
	logic  [3:0] byteEnable_last;
	logic  [3:0] byteEnable_first;
} pcie_requesterRequest_user;

interface pcie_requesterRequest;
	logic [pcieInterfaces::INTERFACEWIDTH-1:0] data;                                    // input wire [255 : 0] s_axis_rq_tdata
	pcie_requesterRequest_user user;                                    // input wire [59 : 0] s_axis_rq_tuser
	logic         last;                                    // input wire s_axis_rq_tlast
	logic   [pcieInterfaces::PCIE_KEEP_BITS-1:0] keep;                                    // input wire [7 : 0] s_axis_rq_tkeep
	logic         valid;                                    // input wire s_axis_rq_tvalid  	
	logic   [3:0] ready;                                    // output wire [3 : 0] s_axis_rq_tready

	modport pcieCore(
		input data,
		input user,
		input last,
		input keep,
		input valid,
		output ready
		);
	
	modport userLogic(
		output data,
		output user,
		output last,
		output keep,
		output valid,
		input ready
	);
endinterface

typedef struct packed {
	logic [3:1] offset;
	logic       isEnd;
} pcie_requesterCompletion_eof_info;

typedef struct packed {
	logic [31:0] parity;
	logic        discontinue;
	pcie_requesterCompletion_eof_info endOfFrame_1;
	pcie_requesterCompletion_eof_info endOfFrame_0;
	logic        startOfFrame_1;
	logic        startOfFrame_0;
	logic [31:0] byteEnable;
} pcie_requesterCompletion_user;

interface pcie_requesterCompletion;
	logic [pcieInterfaces::INTERFACEWIDTH-1:0] data;                                    // output wire [255 : 0] m_axis_rc_tdata
	pcie_requesterCompletion_user user;                                    // output wire [74 : 0] m_axis_rc_tuser
	logic         last;                                    // output wire m_axis_rc_tlast
	logic   [pcieInterfaces::PCIE_KEEP_BITS-1:0] keep;                                    // output wire [7 : 0] m_axis_rc_tkeep
	logic         valid;                                    // output wire m_axis_rc_tvalid
	logic         ready;                                    // input wire [21 : 0] m_axis_rc_tready
	
	modport pcieCore(
		output data,
		output user,
		output last,
		output keep,
		output valid,
		input ready
	);

	modport userLogic(
		input data,
		input user,
		input last,
		input keep,
		input valid,
		output ready
	);
endinterface

/*
 MSI prefix dropped for everything, non MSI signals prefixed with legacy_
 */
interface pcie_interrupt;
	typedef struct packed {
		logic [31:0] physicalFunction1;
		logic [31:0] physicalFunction0;
	} interruptPendingStatus_t;
	
	logic  [3:0] legacy_interrupt;                                 // input wire [3 : 0] int
	logic  [1:0] legacy_pending;                         // input wire [1 : 0] pending
	logic        legacy_sent;                               // output wire sent
	logic  [1:0] enable;                   // output wire [1 : 0] enable
	logic  [5:0] vf_enable;             // output wire [5 : 0] vf_enable
	logic  [5:0] mmenable;               // output wire [5 : 0] mmenable
	logic        mask_update;         // output wire mask_update
	logic [31:0] data;                       // output wire [31 : 0] data
	logic  [3:0] select;                   // input wire [3 : 0] select
	logic [31:0] interruptVector;                         // input wire [31 : 0] int
	interruptPendingStatus_t pending_status;   // input wire [63 : 0] pending_status
	logic        sent;                       // output wire sent
	logic        fail;                       // output wire fail
	logic  [2:0] attr;                       // input wire [2 : 0] attr
	logic        tph_present;         // input wire tph_present
	logic  [1:0] tph_type;               // input wire [1 : 0] tph_type
	logic  [8:0] tph_st_tag;           // input wire [8 : 0] tph_st_tag
	logic  [2:0] function_number; // input wire [2 : 0] function_number
	
	modport pcieCore(
		input  legacy_interrupt,
		input  legacy_pending,
		output legacy_sent,
		output enable,
		output vf_enable,
		output mmenable,
		output mask_update,
		output data,
		input  select,
		input  interruptVector,
		input  pending_status,
		output sent,
		output fail,
		input  attr,
		input  tph_present,
		input  tph_type,
		input  tph_st_tag,
		input  function_number
		);
	
	modport userLogic(
		output legacy_interrupt,
		output legacy_pending,
		input  legacy_sent,
		input  enable,
		input  vf_enable,
		input  mmenable,
		input  mask_update,
		input  data,
		output select,
		output interruptVector,
		output pending_status,
		input  sent,
		input  fail,
		output attr,
		output tph_present,
		output tph_type,
		output tph_st_tag,
		output function_number
	);
endinterface

interface pcie_configuration_flowcontrol;
	typedef enum logic [2:0] {
		RECEIVEAVAILABLE   = 3'b000,
		RECEIVELIMIT       = 3'b001,
		RECEIVECONSUMED    = 3'b010,
		RECEIVEBUFFER      = 3'b011,
		TRANSMITAVAILABLE  = 3'b100,
		TRANSMITLIMIT      = 3'b101,
		TRANSMITCONSUMED   = 3'b110
	} informationType;
	
	logic  [7:0] postedHeader;                                                  // output wire [7 : 0] ph
	logic [11:0] postedData;                                                  // output wire [11 : 0] pd
	logic  [7:0] nonPostedHeader;                                                // output wire [7 : 0] nph
	logic [11:0] nonPostedData;                                                // output wire [11 : 0] npd
	logic  [7:0] completionHeader;                                              // output wire [7 : 0] cplh
	logic [11:0] completionData;                                              // output wire [11 : 0] cpld
	informationType informationSelect;                                                // input wire [2 : 0] sel
	
	modport pcieCore(
		output postedHeader,
		output postedData,
		output nonPostedHeader,
		output nonPostedData,
		output completionHeader,
		output completionData,
		input  informationSelect
	);

	modport userLogic(
		input  postedHeader,
		input  postedData,
		input  nonPostedHeader,
		input  nonPostedData,
		input  completionHeader,
		input  completionData,
		output informationSelect
	);
endinterface

interface pcie_transmitFlowControl;
	logic [1:0] nonPostedHeaderCredits;                                      // output wire [1 : 0] pcie_tfc_nph_av
	logic [1:0] nonPostedDataCredits;                                      // output wire [1 : 0] pcie_tfc_npd_av
	
	modport pcieCore(
		output nonPostedHeaderCredits,
		output nonPostedDataCredits
	);

	modport userLogic(
		input nonPostedHeaderCredits,
		input nonPostedDataCredits
	);
endinterface

interface pcie_configurationStatus;
	typedef enum logic [1:0] { //LS = LINK STATUS
		LS_NO_RECEIVERS  = 2'b00,
		LS_TRAINING      = 2'b01,
		LS_DOWNLINK_INIT = 2'b10,
		LS_LINK_UP       = 2'b11
	} physicalLinkState_t;
	
	typedef enum logic [2:0] {
		PCIE_SPEED_GEN1 = 3'b001,
		PCIE_SPEED_GEN2 = 3'b010,
		PCIE_SPEED_GEN3 = 3'b100
	} pcieSpeed_t;
	
	typedef struct packed {
		logic INTx_1_disable;
		logic busMaster_1_enable;
		logic memorySpace_1_enable;
		logic ioSpace_1_enable;
		logic INTx_0_disable;
		logic busMaster_0_enable;
		logic memorySpace_0_enable;
		logic ioSpace_0_enable;
	} function_status_t;
	
	typedef struct packed {
		logic busMasterEnable;
		logic softwareEnable;
	} virtualFunctionControl_t;
	
	typedef enum logic [2:0] {
		VFP_D0_UNINITIALIZED = 3'b000,
		VFP_D0_ACTIVE        = 3'b001,
		VFP_D1               = 3'b010,
		VFP_D3_HOT           = 3'b100
	} functionPower_t;
	
	typedef enum logic [1:0] {
		LINKPOWERSTATE_L0  = 2'b00,
		LINKPOWERSTATE_L0s = 2'b01,
		LINKPOWERSTATE_L1  = 2'b10,
		LINKPOWERSTATE_L2  = 2'b11
	} linkPowerState_t;
	
	typedef enum logic [1:0] {
		OBFF_DISABLED      = 2'b00,
		OBFF_ENABLED_MSG_A = 2'b01,
		OBFF_ENABLED_MSG_B = 2'b10,
		OBFF_ENABLED_WAKE  = 2'b11
	} optimizedBufferFlush_control_t;
	
	function logic[12:0] payloadSizeToInt(logic[2:0] size);
		return 13'd128 << size;
	endfunction
	
	function logic[12:0] requestSizeToInt(logic[2:0] size);
		return 13'd128 << size;
	endfunction
	
	logic       physicalLinkDown;
	physicalLinkState_t physicalLinkState;
	logic [3:0] negotiatedWidth;
	pcieSpeed_t speed;
	logic [2:0] maxPayloadSize;
	logic [2:0] maxReadRequestSize;
	function_status_t functionStatus;
	functionPower_t [1:0] functionPower;
	virtualFunctionControl_t [5:0] virtualFunctionStatus; //FIXME: verify if the array and the struct are the right way round
	functionPower_t [5:0] virtualFunctionPower;
	linkPowerState_t linkPowerState;
	logic error_correctable;
	logic error_nonfatal;
	logic error_fatal;
	logic latencyToleranceReporting;
	logic [5:0] LTSSM_state; // TODO: create enum
	logic [1:0] rcb_state;
	logic [1:0] dynamicPowerAllocation_substateChange;
	optimizedBufferFlush_control_t optimizedBufferFlush_control;
	logic pl_status_change;
	logic [1:0] tph_requester_enable;
	logic [1:0][2:0] tph_st_mode;
	logic [5:0] virtualFunction_tph_requesterEnable;
	logic [5:0][2:0] virtualFunction_tph_st_mode;
	
	modport pcieCore(
		output physicalLinkDown,
		output physicalLinkState,
		output negotiatedWidth,
		output speed,
		output maxPayloadSize,
		output maxReadRequestSize,
		output functionStatus,
		output functionPower,
		output virtualFunctionStatus,
		output virtualFunctionPower,
		output linkPowerState,
		output error_correctable,
		output error_nonfatal,
		output error_fatal,
		output latencyToleranceReporting,
		output LTSSM_state,
		output rcb_state,
		output dynamicPowerAllocation_substateChange,
		output optimizedBufferFlush_control,
		output pl_status_change,
		output tph_requester_enable,
		output tph_st_mode,
		output virtualFunction_tph_requesterEnable,
		output virtualFunction_tph_st_mode
	);
	
	modport userLogic(
		input  physicalLinkDown,
		input  physicalLinkState,
		input  negotiatedWidth,
		input  speed,
		input  maxPayloadSize,
		input  maxReadRequestSize,
		//input  .maxPayload( 13'h10 << maxPayloadSize), //Oh, if Xilinx knew about modport expressions...
		input  functionStatus,
		input  functionPower,
		input  virtualFunctionStatus,
		input  virtualFunctionPower,
		input  linkPowerState,
		input  error_correctable,
		input  error_nonfatal,
		input  error_fatal,
		input  latencyToleranceReporting,
		input  LTSSM_state,
		input  rcb_state,
		input  dynamicPowerAllocation_substateChange,
		input  optimizedBufferFlush_control,
		input  pl_status_change,
		input  tph_requester_enable,
		input  tph_st_mode,
		input  virtualFunction_tph_requesterEnable,
		input  virtualFunction_tph_st_mode
	);
endinterface

//endpackage
