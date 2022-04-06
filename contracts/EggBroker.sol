// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract EggBroker is Ownable {
    using SafeMath for uint8;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public mebTokenAddress;
    address public eggMebPairAddress;
    address public eggTokenAddress;

    mapping(address => bool) public allAccounts;
    address _creator;

    bool public allowNoneEggSwitch = true;
    uint256[2] levelOneFriendBalanceLimit = [1000 * 10**18, 10000 * 10**18];
    uint256[2] levelTwoFriendBalanceLimit = [2000 * 10**18, 20000 * 10**18];
    uint256[2] levelThreeFriendBalanceLimit = [3000 * 10**18, 30000 * 10**18];

    mapping(address => bool) public agentAddress;
    mapping(address => address) public accountParentAddress;
    mapping(address => uint256) public levelOneFriendCount;
    mapping(address => uint256) public levelTwoFriendCount;
    mapping(address => uint256) public levelThreeFriendCount;

    mapping(address => uint256) public availableRewardBalance;
    mapping(address => uint256) public totalRewardBalance;

    EnumerableSet.AddressSet private goldAgentAddressSet;
    uint256 public goldAgentBalance;
    mapping(address => uint256) public goldAgentRewardBalance;

    uint8 captainMemberRate = 1;
    EnumerableSet.AddressSet private captainMemberSet;
    uint256 public captainMemberBalance = 0;

    uint8 creationMemberRate = 1;
    EnumerableSet.AddressSet private creationMemberSet;
    uint256 public creationMemberBalance = 0;

    constructor() {
        _creator = msg.sender;
    }

    function rewardWithdraw() public {
        require(agentAddress[msg.sender], "you are not agent yet");
        require(_verifySatisfyAgentLevel(msg.sender, 1), "You are no longger a agent");
        uint256 withdrawRewardBalance = availableRewardBalance[msg.sender];
        require(withdrawRewardBalance > 0, "Insufficient of available reward balance");
        availableRewardBalance[msg.sender] = 0;
        IERC20(eggTokenAddress).safeTransfer(msg.sender, withdrawRewardBalance);
    }

    function setParentAddress(address parentAddress) public {
        require(parentAddress != msg.sender, "ParentAddress can`t set youself");
        require(accountParentAddress[parentAddress] != address(0) || parentAddress == _creator, "Parent account is not actived");
        require(accountParentAddress[msg.sender] == address(0), "AccountParentAddress is exist");
        accountParentAddress[msg.sender] = parentAddress;

        levelOneFriendCount[parentAddress] = levelOneFriendCount[parentAddress].add(1);
        address levelTwoFriendAddress = accountParentAddress[parentAddress];
        if (levelTwoFriendAddress != address(0)) {
            levelTwoFriendCount[levelTwoFriendAddress] = levelTwoFriendCount[levelTwoFriendAddress].add(1);
        }
        address levelThreeFriendAddress = accountParentAddress[levelTwoFriendAddress];
        if (levelThreeFriendAddress != address(0)) {
            levelThreeFriendCount[levelThreeFriendAddress] = levelThreeFriendCount[levelThreeFriendAddress].add(1);
        }
    }

    function accountInvite(address inviteAddress) public {
        require(inviteAddress != msg.sender, "Can`t invite youself");
        require(!allAccounts[inviteAddress], "Account is exist");
        require(accountParentAddress[msg.sender] != address(0), "Your account is not actived");
        require(accountParentAddress[inviteAddress] == address(0), "account`s parent address is already exist");
        accountParentAddress[inviteAddress] = msg.sender;

        levelOneFriendCount[msg.sender] = levelOneFriendCount[msg.sender].add(1);
        address levelTwoFriendAddress = accountParentAddress[msg.sender];
        if (levelTwoFriendAddress != address(0)) {
            levelTwoFriendCount[levelTwoFriendAddress] = levelTwoFriendCount[levelTwoFriendAddress].add(1);
        }
        address levelThreeFriendAddress = accountParentAddress[levelTwoFriendAddress];
        if (levelThreeFriendAddress != address(0)) {
            levelThreeFriendCount[levelThreeFriendAddress] = levelThreeFriendCount[levelThreeFriendAddress].add(1);
        }
    }

    function applyAgent() public {
        require(!agentAddress[msg.sender], "You are already an agent");
        require(accountParentAddress[msg.sender] != address(0), "Your account is not actived");
        require(IERC20(mebTokenAddress).balanceOf(msg.sender) >= levelOneFriendBalanceLimit[0], "Insufficient Balance of MEB");
        require(IERC20(eggTokenAddress).balanceOf(msg.sender) >= levelOneFriendBalanceLimit[1] || allowNoneEggSwitch, "Insufficient Balance of EGG");
        agentAddress[msg.sender] = true;
    }

    function applyGoldAgent() public {
        require(!goldAgentAddressSet.contains(msg.sender), "You are already an gold agent");
        require(_verifySatisfyAgentLevel(msg.sender, 3), "You are not an gold agent.");
        require(levelOneFriendCount[msg.sender] >= 5, "You don't invite enough friends");
        goldAgentAddressSet.add(msg.sender);
    }

    function queryGoldAgent(address _address) public view returns (bool) {
        return goldAgentAddressSet.contains(_address);
    }

    function setAllowNoneEggSwitch(bool _allowNoneEggSwitch) public onlyOwner {
        allowNoneEggSwitch = _allowNoneEggSwitch;
    }

    function countGoldAgent() public view returns (uint256) {
        return goldAgentAddressSet.length();
    }

    function processGoldAgentBalance() public {
        address[] memory goldAgentAddress = goldAgentAddressSet.values();
        for (uint256 i = 0; i < goldAgentAddress.length; i++) {
            if (!_verifySatisfyAgentLevel(goldAgentAddress[i], 3) || levelOneFriendCount[msg.sender] < 5) {
                goldAgentAddressSet.remove(goldAgentAddress[i]);
            }
        }
        if (goldAgentAddressSet.length() == 0) {
            return;
        }
        uint256 amountPerGoldAgent = goldAgentBalance.div(goldAgentAddressSet.length());
        goldAgentBalance = 0;
        for (uint160 i = 0; i < goldAgentAddressSet.length(); i++) {
            IERC20(eggTokenAddress).safeTransfer(goldAgentAddressSet.at(i), amountPerGoldAgent);
            goldAgentRewardBalance[goldAgentAddressSet.at(i)] = goldAgentRewardBalance[goldAgentAddressSet.at(i)].add(amountPerGoldAgent);
        }
    }

    function addCaptainMemberAddressBatch(address[] calldata captainMemberAddress) public onlyOwner {
        for (uint256 i = 0; i < captainMemberAddress.length; i++) {
            if (!creationMemberSet.contains(captainMemberAddress[i])) {
                captainMemberSet.add(captainMemberAddress[i]);
            }
        }
    }

    function removeCaptainMemberAddress(address captainMemberAddress) public onlyOwner {
        require(captainMemberSet.contains(captainMemberAddress), "Address is not exist");
        captainMemberSet.remove(captainMemberAddress);
    }

    function allCaptainMemberAddress() public view returns (address[] memory) {
        return captainMemberSet.values();
    }

    function processCaptainMemberFee() public {
        require(captainMemberBalance > 0, "Insufficient Balance of creationMemberBalance");
        require(captainMemberSet.length() > 0, "CreationMember is empty");
        uint256 perCaptainMemberAmount = captainMemberBalance.div(captainMemberSet.length());
        captainMemberBalance = 0;
        for (uint256 i = 0; i < captainMemberSet.length(); i++) {
            IERC20(eggTokenAddress).transfer(captainMemberSet.at(i), perCaptainMemberAmount);
        }
    }

    function addCreationMemberAddressBatch(address[] calldata creationMemberAddress) public onlyOwner {
        for (uint256 i = 0; i < creationMemberAddress.length; i++) {
            if (!creationMemberSet.contains(creationMemberAddress[i])) {
                creationMemberSet.add(creationMemberAddress[i]);
            }
        }
    }

    function removeCreationMemberAddress(address creationMemberAddress) public onlyOwner {
        require(creationMemberSet.contains(creationMemberAddress), "Address is not exist");
        creationMemberSet.remove(creationMemberAddress);
    }

    function allCreationMemberAddress() public view returns (address[] memory) {
        return creationMemberSet.values();
    }

    function processCreationMemberFee() public {
        require(creationMemberBalance > 0, "Insufficient Balance of creationMemberBalance");
        require(creationMemberSet.length() > 0, "CreationMember is empty");
        uint256 perCreationMemberAmount = creationMemberBalance.div(creationMemberSet.length());
        creationMemberBalance = 0;
        for (uint256 i = 0; i < creationMemberSet.length(); i++) {
            IERC20(eggTokenAddress).safeTransfer(creationMemberSet.at(i), perCreationMemberAmount);
        }
    }

    function initEggAddress(address _eggTokenAddress, address _eggMebPairAddress) public onlyOwner {
        require(eggTokenAddress != _eggTokenAddress, "eggTokenAddress is already the value");
        require(eggMebPairAddress != _eggMebPairAddress, "eggMebPairAddress is already the value");
        eggTokenAddress = _eggTokenAddress;
        eggMebPairAddress = _eggMebPairAddress;
    }

    function initParentAddress(address[] calldata _address, address[] calldata _parentAddress) public onlyOwner {
        require(_address.length == _parentAddress.length, "size error");
        for (uint256 i = 0; i < _address.length; i++) {
            if (_address[i] == _parentAddress[i]) {
                continue;
            }
            if (accountParentAddress[_address[i]] != address(0)) {
                continue;
            }
            accountParentAddress[_address[i]] = _parentAddress[i];

            levelOneFriendCount[_parentAddress[i]] = levelOneFriendCount[_parentAddress[i]].add(1);
            address levelTwoFriendAddress = accountParentAddress[_parentAddress[i]];
            if (levelTwoFriendAddress != address(0)) {
                levelTwoFriendCount[levelTwoFriendAddress] = levelTwoFriendCount[levelTwoFriendAddress].add(1);
            }
            address levelThreeFriendAddress = accountParentAddress[levelTwoFriendAddress];
            if (levelThreeFriendAddress != address(0)) {
                levelThreeFriendCount[levelThreeFriendAddress] = levelThreeFriendCount[levelThreeFriendAddress].add(1);
            }
        }
    }

    function resetParentAddress(address _addr) public onlyOwner {
        require(accountParentAddress[_addr] != address(0), "This account is not actived");

        address levelOneFriendAddress = accountParentAddress[_addr];
        accountParentAddress[_addr] = address(0);
        if (levelOneFriendAddress != address(0) && levelOneFriendCount[levelOneFriendAddress] > 0) {
            levelOneFriendCount[_addr] = levelOneFriendCount[levelOneFriendAddress].sub(1);
        }
        address levelTwoFriendAddress = accountParentAddress[levelOneFriendAddress];
        if (levelTwoFriendAddress != address(0) && levelTwoFriendCount[levelTwoFriendAddress] > 0) {
            levelTwoFriendCount[levelTwoFriendAddress] = levelTwoFriendCount[levelTwoFriendAddress].sub(1);
        }
        address levelThreeFriendAddress = accountParentAddress[levelTwoFriendAddress];
        if (levelThreeFriendAddress != address(0) && levelThreeFriendCount[levelThreeFriendAddress] > 0) {
            levelThreeFriendCount[levelThreeFriendAddress] = levelThreeFriendCount[levelThreeFriendAddress].sub(1);
        }
    }

    function _processBuyExchangeFee(address to, uint256 amount) external returns (uint256 mDaoTreasuryAmount) {
        require(msg.sender == eggTokenAddress, "Forbidden!");
        uint256 levelOneFriendFee = amount.mul(5).div(11);
        uint256 levelTwoFriendFee = amount.mul(3).div(11);
        uint256 levelThreeFriendFee = amount.mul(1).div(11);

        creationMemberBalance = creationMemberBalance.add(amount.mul(1).div(11));
        captainMemberBalance = captainMemberBalance.add(amount.mul(1).div(11));

        address levelOneFriend = accountParentAddress[to];
        if (levelOneFriend != address(0) && _verifySatisfyAgentLevel(levelOneFriend, 1)) {
            availableRewardBalance[levelOneFriend] = availableRewardBalance[levelOneFriend].add(levelOneFriendFee);
            totalRewardBalance[levelOneFriend] = totalRewardBalance[levelOneFriend].add(levelOneFriendFee);
        } else {
            mDaoTreasuryAmount = mDaoTreasuryAmount.add(levelOneFriendFee);
        }
        address levelTwoFriend = accountParentAddress[levelOneFriend];
        if (levelTwoFriend != address(0) && _verifySatisfyAgentLevel(levelTwoFriend, 2)) {
            availableRewardBalance[levelTwoFriend] = availableRewardBalance[levelTwoFriend].add(levelTwoFriendFee);
            totalRewardBalance[levelTwoFriend] = totalRewardBalance[levelTwoFriend].add(levelTwoFriendFee);
        } else {
            mDaoTreasuryAmount = mDaoTreasuryAmount.add(levelTwoFriendFee);
        }
        address levelThreeFriend = accountParentAddress[levelTwoFriend];
        if (levelThreeFriend != address(0) && _verifySatisfyAgentLevel(levelThreeFriend, 3)) {
            availableRewardBalance[levelThreeFriend] = availableRewardBalance[levelThreeFriend].add(levelThreeFriendFee);
            totalRewardBalance[levelThreeFriend] = totalRewardBalance[levelThreeFriend].add(levelThreeFriendFee);
        } else {
            mDaoTreasuryAmount = mDaoTreasuryAmount.add(levelThreeFriendFee);
        }

        if (!allAccounts[to]) {
            allAccounts[to] = true;
        }
    }

    function _processStandardTransferFee(address to, uint256 amount) external {
        require(msg.sender == eggTokenAddress, "Forbidden!");
        goldAgentBalance = goldAgentBalance.add(amount);
        if (!allAccounts[to]) {
            allAccounts[to] = true;
        }
    }

    function _verifySatisfyAgentLevel(address _address, uint8 _rewardLevel) internal returns (bool) {
        if (allowNoneEggSwitch) {
            return true;
        }
        if (!agentAddress[_address]) {
            return false;
        }
        uint256 mebTokenBalance = IERC20(mebTokenAddress).balanceOf(_address);
        uint256 eggTokenBalance = IERC20(eggTokenAddress).balanceOf(_address);
        if (mebTokenBalance >= levelThreeFriendBalanceLimit[0] && eggTokenBalance >= levelThreeFriendBalanceLimit[1]) {
            return _rewardLevel <= 3;
        } else if (mebTokenBalance >= levelTwoFriendBalanceLimit[0] && eggTokenBalance >= levelTwoFriendBalanceLimit[1]) {
            return _rewardLevel <= 2;
        } else if (mebTokenBalance >= levelOneFriendBalanceLimit[0] && eggTokenBalance >= levelOneFriendBalanceLimit[1]) {
            return _rewardLevel <= 1;
        } else {
            agentAddress[_address] = false;
            return false;
        }
    }
}
