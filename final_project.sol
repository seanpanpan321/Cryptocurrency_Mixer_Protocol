pragma solidity >=0.7.0 <0.9.0;

struct withdrawApplyTicket {
    uint256 bill;
    uint256 sig;
}

contract mixer {
    //third party: bank
    address payable bank = payable(0x5B38Da6a701c568545dCfcB03FcB875f56beddC4);

    uint256 public depositWindowStart = block.timestamp;
    uint256 public withdrawWindowStart = depositWindowStart + 7 days;
    uint256 public constant amount = 1 ether;
    uint256 public constant signingFee = 0.1 ether;

    //public keys (set by deployer)
    uint128 public N;
    uint128 public e;
    mapping(address => uint256) public blindSignatures; //maps user's address to their blind signatures from the bank

    //for the bank to set and announce public key
    function setKey(uint128 key1, uint128 key2) public {
        require(msg.sender == bank);
        N = key1;
        e = key2;
    }

    modifier canWithdraw {
        require(block.timestamp >= withdrawWindowStart);
        _;
    }

    //local hash helper for hashing bill (s -> h(s))
    function localHashHelper(uint256 bill) public pure returns (bytes32) {
        bytes32 localHashedBill;
        localHashedBill = sha256(abi.encodePacked(bill));
        return localHashedBill;
    }

    //local hide helper (h(s) -> h')
    function localHideHashedBillHelper(bytes32 hashedBill, uint256 r)
        public
        view
        returns (uint256)
    {
        uint128 exp = e;
        uint256 reModN = 1;
        //fast modular exponentiation to hide the hashed bill
        while (exp > 0) {
            if (exp % 2 == 1) {
                reModN = (reModN * r) % N;
            }
            exp = exp >> 1;
            r = (r * r) % N;
        }
        //after while loop, we get r^e mod N

        //h(s) mod N
        uint256 hModN = uint256(hashedBill) % N;

        //hiddenHashedBill = h' = h(s) * r^e % N = [(h mod N)*(r^e mod N)] mod N
        uint256 hiddenHashedBill = (reModN * hModN) % N;
        return hiddenHashedBill;
    }

    //TODO
    //customer call to get signature on hidden hashed bill (buy CD)
    mapping(address => bytes32) public depositWaiting;
    mapping(address => uint256) public depositTime;

    function deposit(bytes32 hiddenHashedBill) public payable {
        require(msg.value == amount + signingFee);
        depositWaiting[msg.sender] = hiddenHashedBill;
        depositTime[msg.sender] = block.timestamp;
    }

    //customer can ask for refund if nothing is signed 24 hours after deposit
    function refundDeposit() public payable {
        require(block.timestamp >= depositTime[msg.sender] + 1 days);
        if (blindSignatures[msg.sender] == 0) {
            payable(msg.sender).transfer(amount + signingFee);
        }
    }

    //for the bank to use sign locally
    function localBlindSign(bytes32 hiddenHashedBill, uint256 d)
        public
        view
        returns (uint256)
    {
        uint256 hhBill = uint256(hiddenHashedBill);

        //signedHiddenHashedBill(result), hiddenHashedBill/hhBill(base), d(exp), N(mod)
        uint256 signedHiddenHashedBill = 1;

        //fast modular exponentiation to sign the hidden hashed bill
        while (d > 0) {
            if (d % 2 == 1) {
                signedHiddenHashedBill = (signedHiddenHashedBill * hhBill) % N;
            }
            d = d >> 1;
            hhBill = (hhBill * hhBill) % N;
        }
        //after while loop we get signature on h'
        return signedHiddenHashedBill;
    }

    //TODO
    //after the bank signs, it keeps a record on the map, for the customer to
    //obtain the blind signature later
    function publishSig(address customer, uint256 blindSig) public {
        blindSignatures[customer] = blindSig;
    }

    //user can call this to get their blind signature from the map
    function getBlindSig() public view returns (uint256) {
        return blindSignatures[msg.sender];
    }

    //local helper to get real signature
    function localObtainSigHelper(
        uint256 signedHiddenHashedBill,
        uint256 rInverse
    ) public pure returns (uint256) {
        return signedHiddenHashedBill * rInverse; //sig is the h(s)^d mod N, valid signature on h(s)
    }

    //customer give bill and signature (which is the CD), and wait for the bank to verify
    mapping(address => withdrawApplyTicket) public withdrawWaiting;

    function applyWithdraw(uint256 bill, uint256 sig) public {
        //the bank now has the information and can start verification
        withdrawApplyTicket memory ticket;
        ticket.bill = bill;
        ticket.sig = sig;

        //add the caller(customer) to waiting list
        withdrawWaiting[msg.sender] = ticket;
    }

    //bank verifies then start withdrawal procedure: pays customer and receives the signing fee
    //(bank will only call this function after it verifies the signature is correct locally)
    mapping(uint256 => bool) public hasWithdrawn;

    function withdraw(address payable customer, uint256 bill)
        public
        canWithdraw
    {
        //avoid double withdrawals
        require(hasWithdrawn[bill] == false); //false is default so this bill is not withdrawn yet
        require(msg.sender == bank);

        //the bank can get the customer address from map (address that applied for withdrawal)
        customer.transfer(amount);
        bank.transfer(signingFee); //incentive for bank to sign and call withdrawal
        hasWithdrawn[bill] = true;
    }

    //local function for the bank to verify if the signature is correct (bank can get bill and sig from ticket)
    function localVerify(
        uint256 bill,
        uint256 sig,
        uint256 d
    ) public view returns (bool) {
        uint256 calculatedSig = 1;
        uint256 hs = uint256(sha256(abi.encodePacked(bill)));

        //fast modular exponentiation to sign the bill
        //calculatedSig(result), hs(base), d(exp), N(mod)
        while (d > 0) {
            if (d % 2 == 1) {
                calculatedSig = (calculatedSig * hs) % N;
            }
            d = d >> 1;
            hs = (hs * hs) % N;
        }
        //after while loop we get h(s)^d mod N

        //check if matches with given sig
        return calculatedSig == sig;
    }
}
