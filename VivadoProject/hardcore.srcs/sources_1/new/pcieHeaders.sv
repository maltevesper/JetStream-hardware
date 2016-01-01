package pcieHeaders;

//Structs here are defined in reverse order to account for the downto definition of the signals.

//general
//mem
//ats
//vendor

typedef logic [10:0] dWordCount_t;

typedef enum logic [3:0] {
	MEM_READ        = 4'b0000,
	MEM_WRITE       = 4'b0001,
	IO_READ         = 4'b0010,
	IO_WRITE        = 4'b0011,
	MEM_FETCH_ADD   = 4'b0100,
	MEM_SWAP        = 4'b0101,
	MEM_CAS         = 4'b0110,
	LOCKED_READ     = 4'b0111,
	TYPE0_CFG_READ  = 4'b1000,
	TYPE1_CFG_READ  = 4'b1001,
	TYPE0_CFG_WRITE = 4'b1010,
	TYPE1_CFG_WRITE = 4'b1011,
	ANY_MESSAGE     = 4'b1100,
	VENDOR          = 4'b1101,
	ATS             = 4'b1110,
	RESERVED__      = 4'b1111
} HeaderType;
	
typedef enum logic [1:0] {
	AT_DEFAULT             = 2'b00,
	AT_TRANSLATION_REQUEST = 2'b01,
	AT_TRANSLATED          = 2'b10,
	AT_RESERVED            = 2'b11
} AddressTypeEncoding;

typedef logic [127:0] unidentifiedHeader;

function HeaderType getHeaderType(unidentifiedHeader header);
	return HeaderType'(header[78:75]);
endfunction

typedef struct packed {
	logic  [0:0] reserved_1;
	logic  [2:0] attributes;
	logic  [2:0] transactionClass;
	logic  [5:0] barAperature;
	logic  [2:0] barID;
	logic  [7:0] target;
	logic  [7:0] tag;
	logic [15:0] requesterID;
	logic  [0:0] reserved_0;
	HeaderType headerType;
	dWordCount_t dwordCount;
	logic [63:2] address;
	AddressTypeEncoding addressType;
} completerRequestMemory;

typedef enum logic [2:0] {
	CC_SUCCESSFUL  = 3'b000,
	CC_UNSUPPORTED = 3'b001,
	CC_ABORT       = 3'b100
} completerCompletionStatusType;

typedef struct packed {
	logic         forceECRC;
	logic  [2:0]  attributes;
	logic  [2:0]  transactionClass;
	logic         completerIdEnable;
	logic  [7:0]  bus;
	logic  [7:0]  target;
	logic  [7:0]  tag;
	logic [15:0]  requesterID;
	logic [47:47] reserved_3;
	logic         posioned;
	completerCompletionStatusType status;
	dWordCount_t  dwords;
	logic [31:30] reserved_2;
	logic         lockedReadCompletion;
	logic [12:0]  bytes;
	logic [15:10] reserved_1;
	AddressTypeEncoding  addressType;
	logic  [7:7]  reserved_0;
	logic  [6:0]  address;
} completerCompletion;

typedef struct packed {
	logic        forceECRC;
	logic  [2:0] attributes;
	logic  [2:0] transactionClass;
	logic        requesterIdEnable;
	logic  [7:0] bus;
	logic  [7:0] target; //device/function
	logic  [7:0] tag;
	logic [15:0] requesterID;
	logic        poisoned;
	HeaderType headerType;
	dWordCount_t dWordCount;
	logic [63:2] address;
	AddressTypeEncoding addressType;
} requesterRequestMemory;

function requesterRequestMemory init_requesterRequestMemory();
	requesterRequestMemory header; // = {default:0};
	header.forceECRC                = 0;
	header.attributes               = 0;
	header.transactionClass         = 0;
	header.requesterIdEnable        = 0;
	header.bus                      = 0;
	header.target                   = 0;
	header.tag                      = 0;
	header.requesterID              = 0;
	header.poisoned                 = 0;
	header.headerType               = MEM_READ;
	header.dWordCount               = 0;
	header.address                  = 0;
	header.addressType              = pcieHeaders::AT_DEFAULT; //TODO: should this be marked as already TRANSLATED instead?
	return header;
endfunction 

typedef enum logic [2:0] {
	RC_SUCCESSFUL                  = 3'b000,
	RC_UNSUPPORTED                 = 3'b001,
	RC_CONFIGURATION_REQUEST_RETRY = 3'b010,
	RC_ABORT                       = 3'b100
} requesterCompletionStatusType;

typedef enum logic [3:0] {
	RC_ERROR_NONE                           = 4'b0000,
	RC_ERROR_POSIONED                       = 4'b0001,
	RC_ERROR_UNSUPPORTED_ABORT_RETRY        = 4'b0010,
	RC_ERROR_NO_DATA_OVERFLOW               = 4'b0011,
	RC_ERROR_ATTRIBUTES_MISSMATCH           = 4'b0100,
	RC_ERROR_START_ADDRESS                  = 4'b0101,
	RC_ERROR_INVALID_TAG                    = 4'b0110,
	RC_ERROR_TIMEOUT                        = 4'b1001,
	RC_ERROR_FUNCTION_LEVEL_RESET_OF_SOURCE = 4'b1000
} requesterCompletionErrorCode;

typedef struct packed {
	logic        reserved_3;
	logic  [2:0] attributes;
	logic  [2:0] transactionClass;
	logic        reserved_2;
	logic  [7:0] bus;
	logic  [7:0] target; //device/function
	logic  [7:0] tag;
	logic [15:0] requesterID;
	logic        reserved_1;
	logic        poisoned;
	requesterCompletionStatusType status;
	dWordCount_t dWordCount;
	logic        reserved_0;
	logic        requestCompleted;
	logic        lockedReadCompletion;
	logic [12:0] byteCount;
	requesterCompletionErrorCode errorCode;
	logic [11:0] address;
} requesterCompletion;

endpackage
