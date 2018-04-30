pragma solidity ^0.4.18;

contract Election {
    
    /* ------------------ Variables --------------------------- */
    
    struct Candidate {
        string symbol;
        uint id;
        address addr;
    }
    
    address private _president;
    
    Candidate[] public candList;
    
    /* HashedTokens => isPresent */
    mapping(bytes32 => bool) private hashDatabase;
    
    /* address of warden => index of Encryption-Decryption pair belonging to this warden */
    mapping(address => uint) private wardens;
    
    /* Amount to be deposited by warden as security */
    uint private securityAmt;
    
    /* address of warden => refundAmt  */
    mapping(address => uint) private refundAmt;
    
    /* reward for warden */
    uint private reward;
    
    /* Begin Candidate Registration */
    uint public bcr;
    
    /* End Candidate Registration */
    uint public ecr;
    
    /* Begin Token Distribution */
    uint public btd;
    
    /* End Token Distribution */
    uint public etd;
    
    /* Begin Vote Casting */
    uint public bvc;
    
    /* End Vote Casting */
    uint public evc;
    
    /* Begin Vote Tally */
    uint public bvt;
    
    bool timesAssigned;
    
    /* present index of key pair to be given */
    uint private idCounter = 0;
    
    /* Number of Encryption-Decryption pairs */
    uint private numKeys = 0;
    
    /* Voter's address => isTokenRecieved */
    mapping(address => bool) private tokenRecieved;
    
    /* List of Encryption Keys */
    mapping(uint => string) private enKeys;
    
    /* voter => recievedEncryptionKey */
    mapping(address => bool) private enKeyRecieved;
    
    /* List of Decryption Keys */
    mapping(uint => string) public deKeys;
    
    mapping(uint => bool) public deKeyVerified;
    
    /* voteBatch[i] => encrypted votes encrypted with i-th encryption key */
    mapping(uint => string[]) private voteBatch;
    
    mapping(uint => string[]) public voteBatchTally;
    
    /* ------------------ Modifiers --------------------------- */    
    
    modifier isPresident {
        require(msg.sender == _president);
        _;
    }
    
    modifier isInVoteCastingTime {
        uint presentTimeStamp = now;
        require(presentTimeStamp > bvc && presentTimeStamp < evc);
        _;
    }
    
    modifier isInCandidateRegistrationTime {
        require(now < ecr && now > bcr);
        _;
    }
    
    modifier hasNotRecievedEncryptionKey {
        require(enKeyRecieved[msg.sender] == false);
        _;
    }
    
    modifier canVoteTallyStart {
        require(now > bvt);
        _;
    }
    
    modifier isWarden {
        require(wardens[msg.sender] > 0);
        _;
    }
    
    modifier beforeVoteCastTime {
        require(now < bvc);
        _;
    }
    
    modifier hasMinSecurityAmount {
        require(msg.value >= securityAmt);
        _;
    }
    
    modifier hasDepositedSecurityAmount {
        require(refundAmt[msg.sender] > 0);
        _;
    }
    
    modifier hasNoToken {
        require(tokenRecieved[msg.sender] == false);
        _;
    }
    
    modifier isInTokenDistributionTime {
        require(now > btd && now < etd);
        _;
    }
    
    /* ------------------ Events --------------------------- */
    
    event encryptedKeyRetrieved(address voter, uint indexOfEDPair, string ek);
    event voteCasted(address voter, bytes32 voterToken, string ev);
    
    /* ------------------ CONSTRUCTOR Methods --------------------------- */
     
    function storeWardens(address[] wardensList) internal {
        for(uint i = 0; i < wardensList.length; i++) {
            wardens[wardensList[i]] = i + 1;
        }
    }
    
    function storeTimes(uint tbcr, uint tecr, uint tbtd, uint tetd, uint tbvc, uint tevc, uint tbvt)  public isPresident returns (bool isSuccessful) {
        bcr = now + tbcr;
        ecr = now + tecr;
        btd = now + tbtd;
        etd = now + tetd;
        bvc = now + tbvc;
        evc = now + tevc;
        bvt = now + tbvt;
        return true;
    }
     
    constructor(address[] wardensList, uint securityAmount, uint rewardAmount) public {
        _president = msg.sender;
        storeWardens(wardensList);
        securityAmt = securityAmount;
        reward = rewardAmount;
    }
    
    /* ------------------ Static Methods --------------------------- */

    function isTokenPresent(bytes32 token) public view returns (bool isPresent) {
        return hashDatabase[keccak256(token)];
    }
    
    function bytes32ToString(bytes32 x) public pure returns (string) {
        bytes memory bytesString = new bytes(32);
        uint charCount = 0;
        for (uint j = 0; j < 32; j++) {
            byte char = byte(bytes32(uint(x) * 2 ** (8 * j)));
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
        }
        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }
        return string(bytesStringTrimmed);
    }
    
    /* ------------------ President Methods --------------------------- */
    
    function getEDPair(uint index) public view isPresident returns (string ek, string dk) {
        return (enKeys[index],deKeys[index]);
    }
    
    function verify(uint index) public isPresident returns (bool isSuccessful) {
        deKeyVerified[index] = true;
        return true;
    }
    
    function voteTally() public isPresident returns (bool isSuccessful) {
        for(uint i = 0; i < numKeys; i++) {
            voteBatchTally[i] = voteBatch[i];
        }
        
        return true;
    }
    
    /* ------------------ Voter Methods --------------------------- */
    
    function getToken() public isInTokenDistributionTime hasNoToken returns (bytes32 token) {
        bytes32 t = keccak256(keccak256(msg.sender));
        hashDatabase[keccak256(t)] = true;
        tokenRecieved[msg.sender] = true;
        return t;
    }
    
    function getEncryptionKey() public isInVoteCastingTime hasNotRecievedEncryptionKey returns (uint indexOfEDPair, string ek) {
        uint i = idCounter + 1;
        idCounter = (idCounter + 1) % numKeys;
        string storage encryptedKey = enKeys[i];
        if(keccak256(encryptedKey) == keccak256("")) {
            return (0, "");
        }
        enKeyRecieved[msg.sender] = true;
        emit encryptedKeyRetrieved(msg.sender, i, encryptedKey);
        return (i, encryptedKey);
    }
    
    function castVote(bytes32 voterToken, uint index, string ev) public isInVoteCastingTime returns (bool isSuccessful) {
        bytes32 hashedToken = keccak256(voterToken);
        require(hashDatabase[hashedToken] == true);
        hashDatabase[hashedToken] = false;
        voteBatch[index].push(ev);
        emit voteCasted(msg.sender, voterToken, ev);
        return true;
    }
    
    /* ------------------ Candidate Methods --------------------------- */
    
    function registerAsCandidate(string symbol) public isInCandidateRegistrationTime returns (bool isSuccessful) {
        uint id = candList.length;
        candList.push(
            Candidate({
                symbol: symbol,
                id: id,
                addr: msg.sender
            })
        );
        
        return true;
    }
    
    /* ------------------ Warden Methods --------------------------- */
    
    function depositSecurity() public isWarden beforeVoteCastTime hasMinSecurityAmount payable returns (bool isSuccessful) {
        refundAmt[msg.sender] = msg.value - securityAmt;
        return true;
    }
    
    function submitEncryptionKey(string ek) public isWarden beforeVoteCastTime hasDepositedSecurityAmount returns (bool isSuccessful) {
        uint id = wardens[msg.sender];
        enKeys[id] = ek;
        numKeys++;
        return true;
    }
    
    function submitDecryptionKey(string dk) public isWarden canVoteTallyStart hasDepositedSecurityAmount returns (bool isSuccessful) {
        uint id = wardens[msg.sender];
        deKeys[id] = dk;
        // Check offline whether ek and dk is correct pair
        return true;
    }
    
    function withdrawReward() public isWarden canVoteTallyStart returns (bool isSuccessful) {
        uint amount = refundAmt[msg.sender];
        refundAmt[msg.sender] = 0;
        if(amount > 0) {
            if(!msg.sender.send(amount)) {
                refundAmt[msg.sender] = amount;
                return false;
            }
        }
        return true;
    }
}