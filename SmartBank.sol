pragma solidity ^0.4.0;

contract SmartBank {
    
    uint private _minBalance = 0.1 ether;
    uint private _depositLimit = 10 ether;
    uint private _withDrawalLimit = 5 ether;
    uint private _transferLimit = 5 ether;
    
    /* Assuming that as normal Deposit will not give any interest */
    uint private normalInterestPercentage = 0;
    
    /* Fixed Deposit amount cannot be withdrawn before the duration of `fixedDepositTime` */
    uint private fixedDepositInterestPercentage = 5;
    uint private fixedDepositTime = 5 years;
    uint private minFixedDepositAmount = 5 ether;
    
    address private _bankManager;
    
    enum BankAccountType { NormalBankAccount, JointBankAccount }
    
    struct BankAccountAddress {
        bool active;
        bool exists;
        uint accountNumber;
        uint lastModified;
    }
    
    mapping(address => BankAccountAddress) private _bankAccountAddresses;
    
    struct BankAccount {
        uint creationTime;
        uint accountNumber;
        address owner;
        address jointOwner;
        uint balance;
        BankAccountType accountType;
        uint fixedDepositBalance;
        uint fixedDepositCreatedOn;
    }

    BankAccount[] private _bankAccounts;
    uint private _totalBankAccounts = 0;
    
    mapping(uint => address) DeactivationApprovedBy;
    
    mapping(address => uint) pendingReturns;
    
    /* ---------------------MODIFIERS--------------------------- */
    modifier hasBankAccount {
        require(_bankAccountAddresses[msg.sender].exists == true);
        _;
    }
    
    modifier hasNoBankAccount {
        require(_bankAccountAddresses[msg.sender].exists == false);
        _;
    }
    
    modifier hasActiveBankAccount {
        require(_bankAccountAddresses[msg.sender].exists && _bankAccountAddresses[msg.sender].active);
        _;
    }
    
    modifier hasMinimumBalance {
        require(msg.value >= _minBalance);
        _;
    }
    
    modifier hasNoDue {
        uint accountNumber = _bankAccountAddresses[msg.sender].accountNumber;
        require(_bankAccounts[accountNumber].balance >= 0);
        _;
    }
    
    modifier isInDepositLimit {
        require(msg.value <= _depositLimit && msg.value >= 0);
        _;
    }
    
    modifier isInWithDrawalLimit {
        require(msg.value <= _withDrawalLimit && msg.value >= 0);
        _;
    }
    
    modifier isInTransferLimit {
        require(msg.value <= _transferLimit && msg.value >= 0);
        _;
    }
    
    modifier hasMinimumFixedDepositAmount {
        require(msg.value >= minFixedDepositAmount);
        _;
    }
    
    modifier hasFixedDeposit {
        uint accountNumber = _bankAccountAddresses[msg.sender].accountNumber;
        require(_bankAccounts[accountNumber].fixedDepositBalance > 0);
        _;
    }
    
    modifier canWithDrawFixedDeposit {
        uint accountNumber = _bankAccountAddresses[msg.sender].accountNumber;
        require(_bankAccounts[accountNumber].fixedDepositCreatedOn + fixedDepositTime <= now);
        _;
    }
    
    /* ---------------------EVENTS----------------------------- */
    
    // this event is fired when a new Bank Account is opened
    event BankAccountOpened(address owner, uint balance, uint accountNumber, uint presentTimeStamp);
    
    // this event is fired when a existing deactivated Bank Account is Reactivated
    event BankAccountReactivated(address owner, uint balance, uint accountNumber, uint presentTimeStamp);
    
    // this event is fired when an active Bank Account is Deactivated
    event BankAccountDeactivated(address owner, uint balance, uint accountNumber, uint presentTimeStamp);
    
    // this event is fired when a certain amount is deposited into a bankAccount
    event AmountDepositSuccessful(address sender, uint balance, uint depositedAmount, uint accountNumber, uint presentTimeStamp);
    
    // this event is fired when a certain amount is withdrew from a bankAccount
    event AmountWithdrawalSuccessful(address owner, uint balance, uint withdrewAmount, uint accountNumber, uint presentTimeStamp);
    
    // this event is fired when a certain amount is transferred from a bankAccount to another bankAccount
    event AmountTransferSuccessful(address from, address to, uint transferAmount, uint presentTimeStamp);
    
    // this event is fired when a new Joint Bank Account is created by one party but still not approved by other
    event JointBankAccountCreated(address owner, address jointOwner, uint balance, uint accountNumber, uint presentTimeStamp);
    
    // this event is fired when a new Joint Bank Account is approved by joint owner and account will become active
    event JointBankAccountApproved(address owner, address jointOwner, uint balance, uint accountNumber, uint presentTimeStamp);
    
    // this event is fired when a new Joint Bank Account deactivation has started and approved by one of the parties only
    event JointBankAccountDeactivationStarted(address approvedBy, uint balance, uint accountNumber, uint presentTimeStamp);
    
    // this event is fired when a new Joint Bank Account is deactivated and approved by both parties
    event JointBankAccountDeactivated(address owner, address jointOwner, uint balance, uint accountNumber, uint presentTimeStamp);
    
    // this event is fired when a Fixed Deposit is created/modified
    event FixedDepositCreated(uint accountNumber, uint fixedDepositAmount, uint presentTimeStamp);
    
    // this event is fired when a Fixed Deposit Amount is withdrew
    event FixedDepositWithdrawalSuccessful(uint accountNumber, uint fixedDepositAmount, uint presentTimeStamp);
    
    event DebugLogger(address val);
    
    /*---------------------CONSTRUCTOR----------------------------- */
    
    function SmartBank() public {
        _bankManager = msg.sender;
    }
    
    
    /* ---------------------STATIC FUNCTIONS----------------------------- */
    
    /**
     * @return accountNumber accountNumber of msg.sender
     */
    function getAccountNumber() public view hasBankAccount returns(uint accountNumber) {
        return _bankAccountAddresses[msg.sender].accountNumber;
    }
    
    /**
     * @return accountBalance accountBalance of msg.sender
     */
    function getAccountBalance() public view hasBankAccount returns(uint accountBalance) {
        uint accountNumber = _bankAccountAddresses[msg.sender].accountNumber;
        return _bankAccounts[accountNumber].balance;
    }
    
    /**
     * @return hasAccount is Bank Account with msg.sender address exists
     */
    function bankAccountExists() public view returns(bool hasAccount) {
        if(_bankAccountAddresses[msg.sender].exists) {
            return true;
        } else {
            return false;
        }
    }
    
    /**
     * @return isActive is Bank Account Active
     */
    function isBankAccountActive() public view returns(bool isActive) {
        if(_bankAccountAddresses[msg.sender].active) {
            return true;
        } else {
            return false;
        }
    }
    
    /**
     * @return isJoint is Bank Account Joint Bank Account
     */
    function isJointAccount() public view returns(bool isJoint) {
        if(bankAccountExists()) {
            uint accountNumber = getAccountNumber();
            if(_bankAccounts[accountNumber].accountType == BankAccountType.JointBankAccount) {
                return true;
            } else {
                return false;
            }
        } else {
            return false;
        }
    }
    
    /**
     * @return fixedDepositBalance fixedDepositBalance of msg.sender
     */
    function getFixedDepositBalance() public view hasBankAccount returns(uint fixedDepositBalance) {
        uint accountNumber = _bankAccountAddresses[msg.sender].accountNumber;
        return _bankAccounts[accountNumber].fixedDepositBalance;
    }
    
    /**
     * @return balance
     */
    function getPendingReturns() public view returns(uint balance) {
        return pendingReturns[msg.sender];
    }
    
    /* ---------------------NORMAL BANK ACCOUNT----------------------------- */
    
    /**
     * @return accountNumber - Your New Account Number of your Bank Account
     */
    function openBankAccount() public hasNoBankAccount hasMinimumBalance payable returns (uint accountNumber) {
        uint newAccountNumber = _totalBankAccounts;
        
        _bankAccounts.push(
            BankAccount({
                creationTime: now,
                accountNumber: newAccountNumber,
                owner: msg.sender,
                jointOwner: address(0),
                balance: msg.value,
                accountType: BankAccountType.NormalBankAccount,
                fixedDepositBalance: 0,
                fixedDepositCreatedOn: 0
            })
        );
        
        _bankAccountAddresses[msg.sender].exists = true;
        _bankAccountAddresses[msg.sender].active = true;
        _bankAccountAddresses[msg.sender].accountNumber = newAccountNumber;
        _bankAccountAddresses[msg.sender].lastModified = now;
        
        _totalBankAccounts++;
        emit BankAccountOpened(msg.sender, msg.value, newAccountNumber, now);
        return newAccountNumber;
    }
    
    function deactivateBankAccount() public hasActiveBankAccount hasNoDue {
        _bankAccountAddresses[msg.sender].active = false;
        _bankAccountAddresses[msg.sender].lastModified = now;
        uint accountNumber = _bankAccountAddresses[msg.sender].accountNumber;
        emit BankAccountDeactivated(msg.sender, _bankAccounts[accountNumber].balance, accountNumber, now);
        
        // transfer the remaining balance to the sender's account
        uint balance = _bankAccounts[accountNumber].balance;
        _bankAccounts[accountNumber].balance = 0;
        pendingReturns[msg.sender] = balance;
    }
    
    function selfDeposit() public hasActiveBankAccount isInDepositLimit payable {
        uint accountNumber = _bankAccountAddresses[msg.sender].accountNumber;
        _bankAccounts[accountNumber].balance += msg.value;
        _bankAccountAddresses[msg.sender].lastModified = now;
        emit AmountDepositSuccessful(msg.sender, _bankAccounts[accountNumber].balance, msg.value, accountNumber, now);
    }
    
    /**
     * @param accountNumber - AccountNumber of the bank Account in which you want to deposit
     */
    function deposit(uint accountNumber) public isInDepositLimit payable {
        require(accountNumber < _totalBankAccounts);
        address owner = _bankAccounts[accountNumber].owner;
        require(_bankAccountAddresses[owner].active);
        _bankAccounts[accountNumber].balance += msg.value;
        _bankAccountAddresses[owner].lastModified = now;
        emit AmountDepositSuccessful(msg.sender, _bankAccounts[accountNumber].balance, msg.value, accountNumber, now);
    }
    
    /**
     * @return isSuccessful - is withdrawal succesful
     */
    function withdraw(uint amount) public hasActiveBankAccount isInWithDrawalLimit returns(bool isSuccesful) {
        uint accountNumber = _bankAccountAddresses[msg.sender].accountNumber;
        require(_bankAccounts[accountNumber].balance - amount >= _minBalance);
        _bankAccounts[accountNumber].balance -= amount;
        pendingReturns[msg.sender] += amount;
        _bankAccountAddresses[msg.sender].lastModified = now;
        emit AmountWithdrawalSuccessful(msg.sender, _bankAccounts[accountNumber].balance, amount, accountNumber, now);
        return true;
    }
    
    function transfer(uint amount, uint recipientAccountNumber) public hasActiveBankAccount isInTransferLimit {
        uint accountNumber = _bankAccountAddresses[msg.sender].accountNumber;
        require(_bankAccounts[accountNumber].balance - amount >= _minBalance);
        
        address recipient = _bankAccounts[recipientAccountNumber].owner;
        require(_bankAccountAddresses[recipient].active);
        
        _bankAccounts[accountNumber].balance -= amount;
        _bankAccounts[recipientAccountNumber].balance += amount;
        
        _bankAccountAddresses[msg.sender].lastModified = now;
        _bankAccountAddresses[recipient].lastModified = now;
        
        emit AmountTransferSuccessful(msg.sender, recipient, amount, now);
    }
    
    /// Fixed Deposit CreationTimeStamp will be reset to presentTimeStamp even if there is some amount in fixedDepositBalance
    function addAFixedDeposit() public hasActiveBankAccount hasMinimumFixedDepositAmount payable {
        uint accountNumber = _bankAccountAddresses[msg.sender].accountNumber;
        _bankAccounts[accountNumber].fixedDepositBalance += msg.value;
        _bankAccounts[accountNumber].fixedDepositCreatedOn = now;
        _bankAccountAddresses[msg.sender].lastModified = now;
        emit FixedDepositCreated(accountNumber, _bankAccounts[accountNumber].fixedDepositBalance, now);
    }
    
    function withdrawFixedDepositAmount() public hasActiveBankAccount hasFixedDeposit canWithDrawFixedDeposit {
        uint accountNumber = _bankAccountAddresses[msg.sender].accountNumber;
        uint amount = _bankAccounts[accountNumber].fixedDepositBalance;
        amount += (amount * fixedDepositInterestPercentage)/100;
        _bankAccounts[accountNumber].balance += amount;
        _bankAccountAddresses[msg.sender].lastModified = now;
        emit FixedDepositWithdrawalSuccessful(accountNumber, _bankAccounts[accountNumber].fixedDepositBalance, now);
    }
    
    /* ---------------------JOINT BANK ACCOUNT----------------------------- */
    
    /**
     * @param jointOwner address of the joint owner should be passed
     * @return accountNumber
     */
    function openJointBankAccount(address jointOwner) public hasNoBankAccount hasMinimumBalance payable returns (uint accountNumber) {
        uint newAccountNumber = _totalBankAccounts;
        _bankAccounts.push(
            BankAccount({
                creationTime: now,
                accountNumber: newAccountNumber,
                owner: msg.sender,
                jointOwner: jointOwner,
                balance: msg.value,
                accountType: BankAccountType.JointBankAccount,
                fixedDepositBalance: 0,
                fixedDepositCreatedOn: 0
            })
        );
        
        _bankAccountAddresses[msg.sender].exists = true;
        
        // account is still not active as other party (joint Owner) should approve this
        _bankAccountAddresses[msg.sender].active = false;
        _bankAccountAddresses[msg.sender].accountNumber = newAccountNumber;
        _bankAccountAddresses[msg.sender].lastModified = now;
        
        _totalBankAccounts++;
        
        emit JointBankAccountCreated(msg.sender, jointOwner, msg.value, accountNumber, now);    
        return newAccountNumber;
    }
    
    /**
     * @param accountNumber accountNumber Of JointBankAccount
     */
    function approveJointBankAccount(uint accountNumber) public hasNoBankAccount {
        require(_totalBankAccounts > accountNumber);
        require(msg.sender == _bankAccounts[accountNumber].jointOwner);
        
        emit DebugLogger(_bankAccounts[accountNumber].owner);
        // address owner = _bankAccounts[accountNumber].owner;
        
        uint presentTimeStamp = now;
        _bankAccountAddresses[msg.sender].accountNumber = accountNumber;
        _bankAccountAddresses[msg.sender].active = true;
        _bankAccountAddresses[msg.sender].exists = true;
        _bankAccountAddresses[msg.sender].lastModified = presentTimeStamp;
        _bankAccountAddresses[_bankAccounts[accountNumber].owner].active = true;
        _bankAccountAddresses[_bankAccounts[accountNumber].owner].lastModified = presentTimeStamp;
        
        emit JointBankAccountApproved(_bankAccounts[accountNumber].owner, msg.sender, _bankAccounts[accountNumber].balance, accountNumber, now);
    }
    
    /**
     * @param accountNumber accountNumber of bank accountNumber
     * @return isSuccessful isDeactivationSuccessful
     */
    function deactivateBankAccount(uint accountNumber) public hasActiveBankAccount hasNoDue returns(bool isSuccessful) {
        require(accountNumber < _totalBankAccounts);
        require(
            _bankAccounts[accountNumber].owner == msg.sender || 
            _bankAccounts[accountNumber].jointOwner == msg.sender);
        uint presentTimeStamp;
        if(DeactivationApprovedBy[accountNumber] != address(0)) {
            address owner1 = DeactivationApprovedBy[accountNumber];
            address owner2 = msg.sender;
            
            if(owner1 == owner2) {
                return true;
            }
            
            if(
                (owner1 == _bankAccounts[accountNumber].owner && owner2 == _bankAccounts[accountNumber].jointOwner) ||
                (owner2 == _bankAccounts[accountNumber].owner && owner1 == _bankAccounts[accountNumber].jointOwner)
              ) {
                  _bankAccountAddresses[owner1].active = false;
                  _bankAccountAddresses[owner2].active = false;
                  DeactivationApprovedBy[accountNumber] = address(0);
                  emit JointBankAccountDeactivated(owner1, owner2, _bankAccounts[accountNumber].balance, accountNumber, now);
                  
                  // transfer the remaining balance to the joint owners' accounts
                  uint balance = _bankAccounts[accountNumber].balance;
                  _bankAccounts[accountNumber].balance = 0;
                  pendingReturns[owner1] = balance/2;
                  balance -= balance/2;
                  pendingReturns[owner2] = balance;
                  presentTimeStamp = now;
                  _bankAccountAddresses[owner1].lastModified = presentTimeStamp;
                  _bankAccountAddresses[owner2].lastModified = presentTimeStamp;
              }
        } else {
            DeactivationApprovedBy[accountNumber] = msg.sender;
            emit JointBankAccountDeactivationStarted(msg.sender, _bankAccounts[accountNumber].balance, accountNumber, now);
            presentTimeStamp = now;
            _bankAccountAddresses[owner1].lastModified = presentTimeStamp;
            _bankAccountAddresses[owner2].lastModified = presentTimeStamp;
        }
        return true;
    }

    /* ---------------------COLLECT PENDING RETURNS-----------------------------*/
    /**
     * @return isSuccessful
     */
    function withdrawPendingReturns() public returns(bool isSuccessful) {
        require(pendingReturns[msg.sender] > 0);
        uint amount = pendingReturns[msg.sender];
        pendingReturns[msg.sender] = 0;
        
        if(!msg.sender.send(amount)) {
            pendingReturns[msg.sender] = amount;
            return false;
        }
        
        return true;
    }
    
}